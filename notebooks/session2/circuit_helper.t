-- Copyright 2015 Stanford University
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

import "regent"

local c = regentlib.c
local std = terralib.includec("stdlib.h")
local fcntl = terralib.includec("fcntl.h")
local unistd = terralib.includec("unistd.h")
rawset(_G, "drand48", std.drand48)
rawset(_G, "srand48", std.srand48)

local CktConfig = require("session1/circuit_config")

local helper = {}

local WIRE_SEGMENTS = 3
local dT = 1e-7

task helper.generate_random_circuit(rn : region(Node),
                                    rw : region(Wire(rn, rn, rn)),
                                    conf : CktConfig)
where reads writes(rn, rw)
do
  var piece_shared_nodes : &uint =
    [&uint](c.malloc([sizeof(uint)] * conf.num_pieces))
  for i = 0, conf.num_pieces do piece_shared_nodes[i] = 0 end

  srand48(conf.random_seed)

  var npieces = conf.num_pieces
  var npp = conf.nodes_per_piece
  var wpp = conf.wires_per_piece

  for p = 0, npieces do
    for i = 0, npp do
      var node = dynamic_cast(ptr(Node, rn), [ptr](p * npp + i))
      if isnull(node) then
        c.printf("the node region was not big enough to pick %dth node\n",
          p * npp + i)
        regentlib.assert(false, "circuit generation failed")
      end
      node.capacitance = drand48() + 1.0
      node.leakage = 0.1 * drand48()
      node.charge = 0.0
      node.voltage = 2 * drand48() - 1.0
    end
  end

  for p = 0, npieces do
    var ptr_offset = p * npp
    for i = 0, wpp do
      var wire = dynamic_cast(ptr(Wire(rn, rn, rn), rw), [ptr](p * wpp + i))
      if isnull(wire) then
        c.printf("the wire region was not big enough to pick %dth wire\n",
          p * wpp + i)
        regentlib.assert(false, "circuit generation failed")
      end
      wire.current.{_0, _1, _2} = 0.0
      wire.voltage.{_1, _2} = 0.0
      wire.resistance = drand48() * 10.0 + 1.0

      -- Keep inductance on the order of 1e-3 * dt to avoid resonance problems
      wire.inductance = (drand48() + 0.1) * dT * 1e-3
      wire.capacitance = drand48() * 0.1

      var in_node = ptr_offset + [uint](drand48() * npp)
      wire.in_node = dynamic_cast(ptr(Node, rn, rn), [ptr](in_node))
      regentlib.assert(not isnull(wire.in_node),
        "picked an invalid random pointer")

      var out_node = 0
      if (100 * drand48() < conf.pct_wire_in_piece) or (npieces == 1) then
        out_node = ptr_offset + [uint](drand48() * npp)
      else
        -- pick a random other piece and a node from there
        var pp = [uint](drand48() * (conf.num_pieces - 1))
        if pp >= p then pp += 1 end

        -- pick an arbitrary node, except that if it's one that didn't used to be shared, make the
        -- sequentially next pointer shared instead so that each node's shared pointers stay compact
        var idx = [uint](drand48() * npp)
        if idx > piece_shared_nodes[pp] then
          idx = piece_shared_nodes[pp]
          piece_shared_nodes[pp] = piece_shared_nodes[pp] + 1
        end
        out_node = pp * npp + idx
      end
      wire.out_node = dynamic_cast(ptr(Node, rn, rn, rn), [ptr](out_node))
      regentlib.assert(not isnull(wire.out_node),
        "picked an invalid random pointer within a piece")
    end
  end
  c.free(piece_shared_nodes)

  -- check validity of pointers
  var invalid_pointers = 0
  for w in rw do
    w.in_node = dynamic_cast(ptr(Node, rn, rn), w.in_node)
    if isnull(w.in_node) then invalid_pointers += 1 end
    w.out_node = dynamic_cast(ptr(Node, rn, rn, rn), w.out_node)
    if isnull(w.out_node) then invalid_pointers += 1 end
  end
  regentlib.assert(invalid_pointers == 0, "there are some invalid pointers")
end

terra helper.calculate_gflops(sim_time : double,
                              flops_calculate_new_currents : uint,
                              flops_distribute_charge: uint,
                              flops_update_voltages : uint,
                              conf : CktConfig)

  -- Compute the floating point operations per second
  var num_circuit_nodes : uint64 = conf.num_pieces * conf.nodes_per_piece
  var num_circuit_wires : uint64 = conf.num_pieces * conf.wires_per_piece

  -- calculate currents
  var operations : uint64 =
  num_circuit_wires * flops_calculate_new_currents * conf.steps
  -- distribute charge
  operations = operations + num_circuit_wires * flops_distribute_charge
  -- update voltages
  operations = operations + num_circuit_nodes * flops_update_voltages
  -- multiply by the number of loops
  operations = operations * conf.num_loops

  var gflops = (1e-9 * operations) / sim_time
  return gflops
end

task helper.dump_graph(conf : CktConfig,
                       rn : region(Node),
                       rw : region(Wire(rn, rn, rn)))
where reads(rn, rw)
do
  var npp = conf.nodes_per_piece
  var wpp = conf.wires_per_piece
  for p = 0, conf.num_pieces do
    c.printf("piece %d:\n", p)
    for i = 0, npp do
      var node = dynamic_cast(ptr(Node, rn, rn), [ptr](p * npp + i))
      c.printf("  node %d\n", __raw(node))
    end
    for i = 0, wpp do
      var wire = dynamic_cast(ptr(Wire(rn, rn, rn), rw), [ptr](p * wpp + i))
      var wire_type = "owned"
      if __raw(wire.out_node).value >= (p + 1) * npp or
         __raw(wire.out_node).value < p * npp
      then
         wire_type = "crossing"
      end
      c.printf("  edge %d: %d -> %d (%s)\n",
        __raw(wire), __raw(wire.in_node), __raw(wire.out_node), wire_type)
    end
  end
end

helper.timestamp = c.legion_get_current_time_in_micros

terra helper.wait_for(x : int)
end

task helper.block(rn : region(Node), rw : region(Wire(rn, rn, rn)))
where reads(rn, rw)
do
  return 1
end

terra helper.read_solution(filename : &int8,
                           node_charge : &float,
                           node_voltage : &float,
                           wire_currents : &float,
                           wire_voltages : &float,
                           num_nodes : int, num_wires : int)
  var fd = fcntl.open(filename, fcntl.O_RDONLY)
  regentlib.assert(fd >= 0, "failed to open input file")

  var offset = 0
  var amt = 0
  var nodes_size = sizeof(float) * num_nodes
  var wires_size = sizeof(float) * num_wires
  amt = unistd.pread(fd, node_charge, nodes_size, offset)
  regentlib.assert(amt == nodes_size, "short read!")
  offset = offset + nodes_size
  amt = unistd.pread(fd, node_voltage, nodes_size, offset)
  regentlib.assert(amt == nodes_size, "short read!")
  offset = offset + nodes_size
  amt = unistd.pread(fd, wire_currents, wires_size * 3, offset)
  regentlib.assert(amt == wires_size * 3, "short read!")
  offset = offset + wires_size * 3
  amt = unistd.pread(fd, wire_voltages, wires_size * 2, offset)
  regentlib.assert(amt == wires_size * 2, "short read!")
  offset = offset + wires_size * 2
end

task helper.initialize_pointers(rpn : region(Node),
                                rsn : region(Node),
                                rgn : region(Node),
                                rw  : region(Wire(rpn, rsn, rgn)))
where reads(rpn, rsn, rgn),
      reads writes(rw.{in_node, out_node})
do
  for w in rw do
    w.in_node = dynamic_cast(ptr(Node, rpn, rsn), w.in_node)
    if isnull(w.in_node) then
      c.printf("validation error: wire %d's in_node is not an owned node\n",
        __raw(w), __raw(w.in_node))
      regentlib.assert(false, "pointer validation failed")
    end
    w.out_node = dynamic_cast(ptr(Node, rpn, rsn, rgn), w.out_node)
    if isnull(w.out_node) then
      c.printf("validation error: wire %d's out_node is invalid: %d\n",
        __raw(w), __raw(w.out_node))
      regentlib.assert(false, "pointer validation failed")
    end
  end
end

return helper
