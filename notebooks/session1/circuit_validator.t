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

local validator = {}

local CktConfig = require("session1/circuit_config")
local helper = require("session1/circuit_helper")
local cmath = terralib.includec("math.h")

local EPS = 1e-4

local terra compare_value(type     : &int8,
                          computed : float,
                          expected : float)
  var diff = cmath.fabs(computed - expected)
  var check = "N"
  var passed = false
  if diff <= EPS then check, passed = "Y", true
  elseif diff / computed <= EPS then check, passed = "Y", true end
  c.printf("  [%s] computed: %.5g, expected: %.5g (%s)\n",
    type, computed, expected, check)
  return passed
end

task validator.validate_solution(rn : region(Node),
                                 rw : region(Wire(rn)),
                                 conf : CktConfig)
where reads writes(rn, rw)
do
  if conf.num_loops ~= 5 or conf.num_pieces ~= 4 or
     conf.nodes_per_piece ~= 4 or conf.wires_per_piece ~= 8 or
     conf.pct_wire_in_piece ~= 80 or conf.random_seed ~= 12345 or
     conf.steps ~= 10000
  then
    c.printf("unknown circuit configuration. skipping validation...\n")
    return
  end

  var num_nodes = conf.num_pieces * conf.nodes_per_piece
  var num_wires = conf.num_pieces * conf.wires_per_piece

  --helper.dump_solution("result_n5_p5_npp4_wpp8_pct80_s12345_s10000.dat",
  --                     __runtime(), __context(),
  --                     __physical(rn), __fields(rn),
  --                     __physical(rw), __fields(rw))

  var node_charge = [&float](c.malloc([sizeof(float)] * num_nodes))
  var node_voltage = [&float](c.malloc([sizeof(float)] * num_nodes))
  var wire_currents = [&float](c.malloc([sizeof(float)] * num_wires * 3))
  var wire_voltages = [&float](c.malloc([sizeof(float)] * num_wires * 2))
  var filename = "session1/result_n5_p5_npp4_wpp8_pct80_s12345_s10000.dat"
  helper.read_solution(filename,
                       node_charge, node_voltage,
                       wire_currents, wire_voltages,
                       num_nodes, num_wires)
  var passed = true
  for n in rn do
    var p = __raw(n).value
    c.printf("node %d:\n", p)
    if not compare_value("charge", n.charge, node_charge[p]) then
      passed = false
    end
    if not compare_value("voltage", n.voltage, node_voltage[p]) then
      passed = false
    end
  end
  for w in rw do
    var p = __raw(w).value
    c.printf("wire %d:\n", p)
    for i = 0, 3 do
      var offset = num_wires * i
      var prefix : int8[16]
      c.sprintf([&int8](prefix), "current%d", i)
      var current : float
      if i == 0 then current = w.current._0
      elseif i == 1 then current = w.current._1
      else current = w.current._2 end
      if not compare_value(prefix, current, wire_currents[p + offset]) then
        passed = false
      end
    end
    for i = 1, 3 do
      var offset = num_wires * (i - 1)
      var prefix : int8[16]
      c.sprintf([&int8](prefix), "voltage%d", i)
      var voltage : float
      if i == 1 then voltage = w.voltage._1
      else voltage = w.voltage._2 end
      if not compare_value(prefix, voltage, wire_voltages[p + offset]) then
        passed = false
      end
    end
  end
  regentlib.assert(passed, "Validation failed!")
  c.printf("Validation passed!\n")
end

return validator
