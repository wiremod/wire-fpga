FPGAGateActions("Execution")

-- FPGAGateActions["execution-last-wild"] = {
-- 	name = "Last",
--   inputs = {"A"},
--   inputtypes = {"WILD"},
--   outputs = {"Out"},
--   outputtypes = {"LINKED"},
--   neverActive = true,
--   output = function(gate)
--     return gate.value
--   end,
--   postCycle = function(gate, value)
--     gate.value = value
-- 	end,
-- }

FPGAGateActions["execution-last-normal"] = {
  name = "Last Normal",
  inputs = {"A"},
  inputtypes = {"NORMAL"},
  outputs = {"Out"},
  outputtypes = {"NORMAL"},
  neverActive = true,
  output = function(gate, value)
    gate.memory = value
    return gate.value
  end,
  reset = function(gate)
    gate.value = 0
    gate.memory = 0
  end,
  postCycle = function(gate)
    gate.value = gate.memory
  end,
}

FPGAGateActions["execution-last-vector"] = {
  name = "Last Vector",
  inputs = {"A"},
  inputtypes = {"VECTOR"},
  outputs = {"Out"},
  outputtypes = {"VECTOR"},
  neverActive = true,
  output = function(gate, value)
    gate.memory = value
    return gate.value
  end,
  reset = function(gate)
    gate.value = Vector(0, 0, 0)
    gate.memory = Vector(0, 0, 0)
  end,
  postCycle = function(gate)
    gate.value = gate.memory
  end,
}

FPGAGateActions["execution-last-angle"] = {
  name = "Last Angle",
  inputs = {"A"},
  inputtypes = {"ANGLE"},
  outputs = {"Out"},
  outputtypes = {"ANGLE"},
  neverActive = true,
  output = function(gate, value)
    gate.memory = value
    return gate.value
  end,
  reset = function(gate)
    gate.value = Angle(0, 0, 0)
    gate.memory = Angle(0, 0, 0)
  end,
  postCycle = function(gate)
    gate.value = gate.memory
  end,
}

FPGAGateActions["execution-last-string"] = {
  name = "Last String",
  inputs = {"A"},
  inputtypes = {"STRING"},
  outputs = {"Out"},
  outputtypes = {"STRING"},
  neverActive = true,
  output = function(gate, value)
    gate.memory = value
    return gate.value
  end,
  reset = function(gate)
    gate.value = ""
    gate.memory = ""
  end,
  postCycle = function(gate)
    gate.value = gate.memory
  end,
}

