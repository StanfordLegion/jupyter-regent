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
local cstring = terralib.includec("string.h")

local CktConfig = require("session1/circuit_config")

local validator = {}

task validator.validate_partitions(conf       : CktConfig,
                                   rn         : region(Node),
                                   rw         : region(Wire(rn)),
                                   pn_private : partition(disjoint, rn),
                                   pn_shared  : partition(disjoint, rn),
                                   pn_ghost   : partition(aliased,  rn),
                                   pw         : partition(disjoint, rw))
where reads(rn, rw)
do
  var np = conf.num_pieces
  var npp = conf.nodes_per_piece
  var wpp = conf.wires_per_piece
  var num_nodes = np * npp
  var num_wires = np * wpp
  var EXP_NONE = 0
  var EXP_PRIVATE = 1
  var EXP_MAYBE_SHARED = 2
  var EXP_SHARED = 3
  var EXP_MAYBE_GHOST = 4
  var EXP_GHOST = 5
  var exp_node_state : &int = [&int](c.malloc([sizeof(int)] * num_nodes))

  var valid = true
  var maybes_used = false
  for p = 0, conf.num_pieces do
    var rprivate = pn_private[p]
    var rshared  = pn_shared[p]
    var rghost   = pn_ghost[p]
    var rwprivate = pw[p]

    var start_node_id = npp * p
    var end_node_id   = npp * (p + 1) - 1
    var start_wire_id = wpp * p
    var end_wire_id   = wpp * (p + 1) - 1

    c.printf("piece %d:\n", p)

    cstring.memset(exp_node_state, EXP_NONE, num_nodes * [sizeof(int)])

    for n = start_node_id, end_node_id + 1 do
      exp_node_state[n] = EXP_PRIVATE
    end

    -- look at all wires
    for w in rw do
      var wire = __raw(w).value
      var in_node = __raw(w.in_node).value
      var out_node = __raw(w.out_node).value
      
      if start_wire_id <= wire and wire <= end_wire_id then
	-- owned wire, might point outside to a ghost
	if not(start_node_id <= out_node and out_node <= end_node_id) then
	  -- promote in_node to MAYBE_SHARED if it's PRIVATE
	  if exp_node_state[in_node] == EXP_PRIVATE then
	    exp_node_state[in_node] = EXP_MAYBE_SHARED
	  end
	  exp_node_state[out_node] = EXP_GHOST
	end
      else
	-- somebody else's wire, might refer to our node making it shared
	if start_node_id <= out_node and out_node <= end_node_id then
	  exp_node_state[out_node] = EXP_SHARED
	  if exp_node_state[in_node] < EXP_GHOST then
	    exp_node_state[in_node] = EXP_MAYBE_GHOST
	  end
	end
      end
    end

    -- check private nodes first
    for n in rn do
      var node = __raw(n).value
      var act = dynamic_cast(ptr(Node, rprivate), n) ~= null(ptr(Node, rprivate))
      if act then
	if exp_node_state[node] == EXP_PRIVATE then
	  c.printf("  private node %d (%s)\n", __raw(n), "ok")
	elseif exp_node_state[node] == EXP_MAYBE_SHARED then
	  c.printf("  private node %d (%s)\n", __raw(n), "ok")
	  exp_node_state[node] = EXP_PRIVATE
	else
	  c.printf("  private node %d (%s)\n", __raw(n), "ERROR")
	  valid = false
	end
      else
	if exp_node_state[node] == EXP_PRIVATE then
	  c.printf("  private node %d (%s)\n", __raw(n), "MISSING")
	  valid = false
	elseif exp_node_state[node] == EXP_MAYBE_SHARED then
	  maybes_used = true
	  exp_node_state[node] = EXP_SHARED -- must be shared then
	end
      end
    end

    -- now shared nodes
    for n in rn do
      var node = __raw(n).value
      var act = dynamic_cast(ptr(Node, rshared), n) ~= null(ptr(Node, rshared))
      if act then
	if exp_node_state[node] == EXP_SHARED then
	  c.printf("  shared node %d (%s)\n", __raw(n), "ok")
	else
	  c.printf("  shared node %d (%s)\n", __raw(n), "ERROR")
	  valid = false
	end
      else
	if exp_node_state[node] == EXP_SHARED then
	  c.printf("  shared node %d (%s)\n", __raw(n), "MISSING")
	  valid = false
	end
      end
    end

    -- now ghost nodes
    for n in rn do
      var node = __raw(n).value
      var act = dynamic_cast(ptr(Node, rghost), n) ~= null(ptr(Node, rghost))
      if act then
	if exp_node_state[node] == EXP_GHOST then
	  c.printf("  ghost node %d (%s)\n", __raw(n), "ok")
	elseif exp_node_state[node] == EXP_MAYBE_GHOST then
	  c.printf("  ghost node %d (%s)\n", __raw(n), "ok")
	  exp_node_state[node] = EXP_GHOST
	  maybes_used = true
	else
	  c.printf("  ghost node %d (%s)\n", __raw(n), "ERROR")
	  valid = false
	end
      else
	if exp_node_state[node] == EXP_GHOST then
	  c.printf("  ghost node %d (%s)\n", __raw(n), "MISSING")
	  valid = false
	elseif exp_node_state[node] == EXP_MAYBE_GHOST then
	  exp_node_state[node] = EXP_NONE
	end
      end
    end

    -- finally check wires
    for w in rw do
      var wire = __raw(w).value
      var in_node = __raw(w.in_node).value
      var out_node = __raw(w.out_node).value
      var act = dynamic_cast(ptr(Wire(rn), rwprivate), w) ~= null(ptr(Wire(rn), rwprivate))
      if act then
	if start_wire_id <= wire and wire <= end_wire_id then
	  c.printf("  edge %d: %d -- %d (%s)\n",
	     __raw(w), in_node, out_node, "ok")
	else
	  c.printf("  edge %d: %d -- %d (%s)\n",
	     __raw(w), in_node, out_node, "ERROR")
	  valid = false
	end
      else
	if start_wire_id <= wire and wire <= end_wire_id then
	  c.printf("  edge %d: %d -- %d (%s)\n",
	     __raw(w), in_node, out_node, "MISSING")
	  valid = false
	end
      end
    end
  end
  regentlib.assert(valid, "Some of partitions are invalid")
  if maybes_used then
    c.printf("Your partitions have a few more shared/ghost nodes than necessary, but are\n")
    c.printf("consistent.  You may proceed to the next part or continue working.\n")
  else
    c.printf("Your partitions pass the validation! Proceed to the next part.\n")
  end
  c.free(exp_node_state)
end

return validator
