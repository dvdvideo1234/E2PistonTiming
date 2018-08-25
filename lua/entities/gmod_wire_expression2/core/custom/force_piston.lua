local sKey, tF = "wire_e2_force_piston", {}

tF[1] = function(R, A, B) return ((R >= A || R < B) and 1 or -1) end
tF[2] = function(R, A, B) return ((R <= A || R > B) and -1 or 1) end
tF[3] = function(R, A, B) return ((R <= A) and -1 or 1) end

e2function void entity:setPiston(number iD, number nA)
  if(not (this and this:IsValid())) then return end
  local tP = this[sKey]; if(not tP) then this[sKey] = {}; tP = this[sKey] end
  local nB, iS = (((nA + 360) % 360) - 180), 0
  if(nA > 0) then iS = 1 elseif(nA < 0) then iS = 2 else iS = 3 end
  tP[iD] = {nA, nB, tF[iS]}
end

e2function void entity:setPiston(string iD, number nA)
  if(not (this and this:IsValid())) then return end
  local tP = this[sKey]; if(not tP) then this[sKey] = {}; tP = this[sKey] end
  local nB, iS = (((nA + 360) % 360) - 180), 0
  if(nA > 0) then iS = 1 elseif(nA < 0) then iS = 2 else iS = 3 end
  tP[iD] = {nA, nB, tF[iS]}
end

e2function number entity:getPiston(number iD, number nR)
  if(not (this and this:IsValid())) then return 0 end
  local tP = this[sKey]; if(not tP) then return 0 end
  tP = tP[iD]; if(not tP) then return 0 end
  return tP[3](nR, tP[1], tP[2])
end

e2function number entity:getPiston(string iD, number nR)
  if(not (this and this:IsValid())) then return 0 end
  local tP = this[sKey]; if(not tP) then return 0 end
  tP = tP[iD]; if(not tP) then return 0 end
  return tP[3](nR, tP[1], tP[2])
end

e2function void entity:remPiston(number iD)
  if(not (this and this:IsValid())) then return end
  local tP = this[sKey]; if(not tP) then return end
  tP[iD] = nil
end

e2function void entity:remPiston(string iD)
  if(not (this and this:IsValid())) then return end
  local tP = this[sKey]; if(not tP) then return end
  tP[iD] = nil
end

e2function void entity:clrPiston()
  if(not (this and this:IsValid())) then return end
  if(not this[sKey]) then return end
  this[sKey] = nil
end

e2function number entity:cntPiston()
  if(not (this and this:IsValid())) then return 0 end
  local tP = this[sKey]; if(not tP) then return 0 end
  return #tP
end

e2function number entity:allPiston()
  if(not (this and this:IsValid())) then return 0 end
  local tP = this[sKey]; if(not tP) then return 0 end
  local iA = 0; for key, val in pairs(tP) do iA = iA + 1 end
  return iA
end

