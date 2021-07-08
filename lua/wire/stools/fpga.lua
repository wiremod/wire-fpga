WireToolSetup.setCategory("Chips, Gates", "Advanced")
WireToolSetup.open("fpga", "FPGA", "gmod_wire_fpga", nil, "FPGAs")

if CLIENT then
	language.Add("Tool.wire_fpga.name", "FPGA Tool (Wire)")
	language.Add("Tool.wire_fpga.desc", "Spawns a field programmable gate array for use with the wire system.")
	language.Add("ToolWirecpu_Model",	"Model:" )
	TOOL.Information = {
		{ name = "left", text = "Upload program to FPGA" },
		{ name = "right", text = "Open editor" },
		{ name = "reload", text = "Reset" }
	}
end
WireToolSetup.BaseLang()
WireToolSetup.SetupMax(40)

TOOL.ClientConVar = {
	model						 = "models/bull/gates/processor.mdl",
	filename					= "",
}

if CLIENT then
	------------------------------------------------------------------------------
	-- Make sure firing animation is displayed clientside
	------------------------------------------------------------------------------
	function TOOL:LeftClick()	return true end
	function TOOL:Reload()		 return true end
	function TOOL:RightClick() return false end
end

if SERVER then
	util.AddNetworkString("FPGA_Upload")
	util.AddNetworkString("FPGA_Download")
	util.AddNetworkString("FPGA_OpenEditor")
	util.AddNetworkString("FPGA_Convert")

	-- Reset
	function TOOL:Reload(trace)
		if trace.Entity:IsPlayer() then return false end
		if CLIENT then return true end

		local player = self:GetOwner()

		if IsValid(trace.Entity) and trace.Entity:GetClass() == "gmod_wire_fpga" then
			trace.Entity:Reset()
			return true
		else
			return false
		end
	end

	-- Spawn or upload
	function TOOL:CheckHitOwnClass(trace)
		return trace.Entity:IsValid() and (trace.Entity:GetClass() == "gmod_wire_fpga")
	end
	function TOOL:LeftClick_Update(trace)
		self:Upload(trace.Entity)
	end
	function TOOL:MakeEnt(ply, model, Ang, trace)
		local ent = WireLib.MakeWireEnt(ply, {Class = self.WireClass, Pos=trace.HitPos, Angle=Ang, Model=model})
		return ent
	end
	function TOOL:PostMake(ent)
		self:Upload(ent)
	end

	function TOOL:BuildGateTable(baseEntity)
		-- Remove these functions when Wiremod exposes it via E2Lib!
		local function buildFilter(filters)
			local function caps(text)
				local capstext = text:sub(1,1):upper() .. text:sub(2):lower()
				if capstext == "Nocollide" then return "NoCollide" end
				if capstext == "Advballsocket" then return "AdvBallsocket" end
				return capstext
			end
			local filter_lookup = {}
		
			if #filters == 0 or (#filters == 1 and filters[1] == "") then -- No filters given, same as "All"
				filter_lookup.Constraints = true
				filter_lookup.Parented = true
				filter_lookup.Wires = true
			else
				for i=1,#filters do
					local filter = filters[i]
					if type(filter) == "string" then
						local bool = true
						if string.sub(filter,1,1) == "-" or string.sub(filter,1,1) == "!" then -- check for negation
							bool = false
							filter = string.sub(filter,2)
						end
		
						filter = caps(filter)
		
						-- correct potential mistakes
						if filter == "Constraint" then filter = "Constraints"
						elseif filter == "Parent" or filter == "Parents" then filter = "Parented"
						elseif filter == "Wire" then filter = "Wires" end
		
						if filter == "All" then
							if bool then -- "all" can't be negated
								filter_lookup.Constraints = true
								filter_lookup.Parented = true
								filter_lookup.Wires = true
							end
						else
							filter_lookup[filter] = bool
						end
					end
				end
			end
		
			return filter_lookup
		end
		local function checkFilter(constraintType,filter_lookup)
			if filter_lookup.Constraints -- check if we allow all constraints
				and not (filter_lookup[constraintType] == false) -- but also if this specific constraint hasn't been negated
				then return true end
		
			return filter_lookup[constraintType] == true -- check if this specific constraint has been added to the filter
		end
		local getConnectedEntities
		local function getConnectedEx(e, filter_lookup, result, already_added)
			if IsValid(e) and not already_added[e] then
				getConnectedEntities(e, filter_lookup, result, already_added)
			end
		end
		getConnectedEntities = function(ent, filter_lookup, result, already_added)
			result = result or {}
			already_added = already_added or {}
		
			result[#result+1] = ent
			already_added[ent] = true
		
			if filter_lookup then
				if filter_lookup.Parented then -- add parented entities
					getConnectedEx(ent:GetParent(),filter_lookup, result, already_added)
					for _, e in pairs(ent:GetChildren()) do
						getConnectedEx( e, filter_lookup, result, already_added )
					end
				end
		
				if filter_lookup.Wires then -- add wired entities
					for _, i in pairs(ent.Inputs or {}) do
						getConnectedEx( i.Src, filter_lookup, result, already_added )
					end
		
					for _, o in pairs(ent.Outputs or {}) do
						getConnectedEx( o.Src, filter_lookup, result, already_added )
					end
				end
			end
		
			for _, con in pairs( ent.Constraints or {} ) do -- add constrained entities
				if IsValid(con) then
					if filter_lookup and not checkFilter(con.Type,filter_lookup) then -- skip if it doesn't match the filter
						continue
					end
		
					for i=1, 6 do
						getConnectedEx( con["Ent"..i], filter_lookup, result, already_added )
					end
				end
			end
		
			return result
		end
		local contraption = getConnectedEntities(baseEntity, buildFilter({"all"}))

		local planes = {}

		local allgates = {}
		for i=1,#contraption do
			local ent = contraption[i]
			if IsValid(ent) and ent:GetClass() == "gmod_wire_gate" then
				allgates[ent] = true
			end
		end

		local function newPlane(pos, up, forward)
			local plane = {
				pos = pos,
				up = up,
				forward = forward,
				gates = {}
			}

			planes[#planes+1] = plane
			return plane
		end

		-- distance to plane
		local function distanceToPlane(plane, pos)
			return plane.up:Dot(pos-plane.pos)
		end

		local function projectToPlane(plane, pos)
			local dist = distanceToPlane(plane, pos)

			local projectedPoint = pos - plane.up * dist
			local rotatedPoint = WorldToLocal(projectedPoint, Angle(), plane.pos, plane.forward:AngleEx(plane.up))

			return {x = math.Round(rotatedPoint.x,2), y = math.Round(rotatedPoint.y,2)}
		end

		-- returns difference in plane's normal vs gate's up direction in radians
		local function normDiff(plane, up)
			local angle = math.acos(plane.up:Dot(up))
			if angle ~= angle then return 0 end -- if it's not equal to itself then it's NaN
			return angle 
		end

		local maxNormDiff = math.rad(10) -- convert 10 degrees to radians

		local function getMatchingPlane(entPos, entUp, entForward)

			for i=1,#planes do
				if math.abs(distanceToPlane(planes[i], entPos)) < 20 and
					normDiff(planes[i], entUp) <maxNormDiff  then 
						return planes[i]
				end
			end

			return newPlane(entPos, entUp, entForward)
		end

		local function getGateInfo(plane, ent, projectedPos)
			local gate = {
				id = ent:EntIndex(),
				action = ent.action,
				pos = projectedPos
			}

			if ent.Inputs then
				gate.inputs = {}
				for inputname, inputdata in pairs(ent.Inputs) do
					if inputdata.Src and IsValid(inputdata.Src) then
						gate.inputs[inputname] = {
							src = inputdata.Src:EntIndex(),
							name = inputdata.SrcId
						}
					end
				end
				if not next(gate.inputs) then gate.inputs = nil end
			end

			if ent.Outputs then
				gate.outputs = {}
				for outputname, outputdata in pairs(ent.Outputs) do
					local needsoutput = false
					for i=1,#outputdata.Connected do
						if not allgates[outputdata.Connected[i].Entity] then
							needsoutput = true
							break
						end
					end

					if needsoutput then
						gate.outputs[outputname] = true
					end
				end
				if not next(gate.outputs) then gate.outputs = nil end
			end

			return gate
		end

		for i=1,#contraption do
			local ent = contraption[i]
			if IsValid(ent) and ent:GetClass() == "gmod_wire_gate" then
				local entPos = baseEntity:WorldToLocal(ent:GetPos())
				local entUp = baseEntity:WorldToLocal(ent:GetUp()*10000 + baseEntity:GetPos()):GetNormalized() -- using *10000 & normalized fixes some rounding errors
				local entForward = baseEntity:WorldToLocal(ent:GetForward()*10000 + baseEntity:GetPos()):GetNormalized()

				local plane = getMatchingPlane(entPos, entUp, entForward)
				local projectedPos = projectToPlane(plane, entPos)
				plane.gates[#plane.gates+1] = getGateInfo(plane, ent, projectedPos)
			end
		end

		return planes
	end

	-- Open editor
	function TOOL:RightClick(trace)
		if trace.Entity:IsPlayer() then return false end

		if IsValid(trace.Entity) and trace.Entity:GetClass() == "gmod_wire_fpga" then
			self:Download(trace.Entity)
			return true
		end

		if IsValid(trace.Entity) and trace.Entity:GetClass() == "gmod_wire_gate" then
			local tbl = self:BuildGateTable(trace.Entity)

			-- todo
			net.Start("FPGA_Convert") net.WriteTable(tbl) net.Send(self:GetOwner())
			return true
		end


		net.Start("FPGA_OpenEditor") net.Send(self:GetOwner())
		return false
	end



	------------------------------------------------------------------------------
	-- Uploading (Server -> Client -> Server)
	------------------------------------------------------------------------------
	-- Send request to client for FPGA data
	function TOOL:Upload(ent)
		net.Start("FPGA_Upload")
			net.WriteInt(ent:EntIndex(), 32)
		net.Send(self:GetOwner())
	end
	------------------------------------------------------------------------------
	-- Downloading (Server -> Client)
	------------------------------------------------------------------------------
	-- Send FPGA data to client
	function TOOL:Download(ent)
		local player = self:GetOwner()

		if not hook.Run("CanTool", player, WireLib.dummytrace(ent), "wire_fpga") then
			WireLib.AddNotify(player, "You're not allowed to download from this FPGA (ent index: " .. ent:EntIndex() .. ").", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1)
			return
		end

		net.Start("FPGA_Download")
			net.WriteString(ent:GetOriginal())
		net.Send(player)
	end
end
if CLIENT then
	--------------------------------------------------------------
	-- Clientside Send
	--------------------------------------------------------------
	function WireLib.FPGAUpload(targetEnt, data)
		if type(targetEnt) == "number" then targetEnt = Entity(targetEnt) end
		targetEnt = targetEnt or LocalPlayer():GetEyeTrace().Entity
		
		if (not IsValid(targetEnt) or targetEnt:GetClass() ~= "gmod_wire_fpga") then
			WireLib.AddNotify("FPGA: Invalid FPGA entity specified!", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1)
			return
		end
		
		if not data and not FPGA_Editor then 
			--WireLib.AddNotify("FPGA: No code specified!", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1)
			return 
		end
		data = data or FPGA_Editor:GetData()

		local bytes = #data

		if bytes > 64000 then
			WireLib.AddNotify("FPGA: Code too large (exceeds 64kB)!", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1)
			return
		end
		
		net.Start("FPGA_Upload")
			net.WriteEntity(targetEnt)
			net.WriteString(data)
		net.SendToServer()
	end
	
	-- Received request to upload
	net.Receive("FPGA_Upload", function(len, ply)
		local entid = net.ReadInt(32)
		timer.Create("FPGA_Upload_Delay",0.03,30,function() -- The new net library is so fast sometimes the chip gets fully uploaded before the entity even exists.
			if IsValid(Entity(entid)) then
				WireLib.FPGAUpload(entid)
				timer.Remove("FPGA_Upload_Delay")
				timer.Remove("FPGA_Upload_Delay_Error")
			end
		end)
		timer.Create("FPGA_Upload_Delay_Error",0.03*31,1,function() WireLib.AddNotify("FPGA: Invalid FPGA entity specified!", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1) end)
	end)

	--------------------------------------------------------------
	-- Clientside Receive
	--------------------------------------------------------------
	-- Received download data
	net.Receive("FPGA_Download", function(len, ply)
		if not FPGA_Editor then
			FPGA_Editor = vgui.Create("FPGAEditorFrame")
			FPGA_Editor:Setup("FPGA Editor", "fpgachip")
		end

		local data = net.ReadString()

		FPGA_Editor:Open(nil, data, true)
	end)
end

if SERVER then
	--------------------------------------------------------------
	-- Serverside Receive
	--------------------------------------------------------------
	-- Receive FPGA data from client
	net.Receive("FPGA_Upload", function(len, ply)
		local chip = net.ReadEntity()
		--local numpackets = net.ReadUInt(16)
	
		if not IsValid(chip) or chip:GetClass() ~= "gmod_wire_fpga" then
			WireLib.AddNotify(ply, "FPGA: Invalid FPGA chip specified. Upload aborted.", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1)
			return
		end

		if not hook.Run("CanTool", ply, WireLib.dummytrace(chip), "wire_fpga") then
			WireLib.AddNotify(ply, "FPGA: You are not allowed to upload to the target FPGA chip. Upload aborted.", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1)
			return
		end
		
		local data = net.ReadString()
		local ok, ret = pcall(WireLib.von.deserialize, data)
		
		if ok then
			chip:Upload(ret)
		else
			WireLib.AddNotify(ply, "FPGA: Upload failed! Error message:\n" .. ret, NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1)
		end
	end)

end



if CLIENT then
	------------------------------------------------------------------------------
	-- Open FPGA editor
	------------------------------------------------------------------------------
	function FPGA_OpenEditor()
		if not FPGA_Editor then
			FPGA_Editor = vgui.Create("FPGAEditorFrame")
			FPGA_Editor:Setup("FPGA Editor", "fpgachip")
		end
		FPGA_Editor:Open()
	end

	net.Receive("FPGA_OpenEditor", FPGA_OpenEditor)

	------------------------------------------------------------------------------
	-- Convert Gate Network
	------------------------------------------------------------------------------
	net.Receive("FPGA_Convert", function(len, ply)
		local planes = net.ReadTable()
		FPGA_OpenEditor()

		if planes and next(planes) ~= nil then
			FPGA_Editor:NewChip(false)
			local editor = FPGA_Editor:GetCurrentEditor()

			local function rectanglesIntersect(minAx, minAy, maxAx, maxAy,
											   minBx, minBy, maxBx, maxBy)
				-- https://stackoverflow.com/a/16012490
				local aLeftOfB = maxAx < minBx;
				local aRightOfB = minAx > maxBx;
				local aAboveB = minAy > maxBy;
				local aBelowB = maxAy < minBy;

				return not (aLeftOfB or aRightOfB or aAboveB or aBelowB)
			end

			local already_placed = {}
			local all_gates = {}

			local GATE_PADDING = 8
			local PLANE_PADDING = FPGANodeSize + 5
			local inputsPosOffset, outputsPosOffset = 0, 0

			-- create gates at the correct positions
			for _, plane in pairs(planes) do
				-- these values determine the size of the plane
				local minx, miny, maxx, maxy = 0,0,0,0
				local maxGateHeight = 0

				for _, gate in pairs(plane.gates) do
					-- calculate size
					minx = math.min(minx,gate.pos.x)
					miny = math.min(miny,gate.pos.y)
					maxx = math.max(maxx,gate.pos.x)
					maxy = math.max(maxy,gate.pos.y)
					maxGateHeight = math.max(gate.inputs and #gate.inputs or 1, gate.outputs and #gate.outputs or 1) * FPGANodeSize

					editor:CreateNode({
						type = "wire",
						gate = gate.action
					},gate.pos.x,gate.pos.y)
					gate.fpga_gate = editor.Nodes[#editor.Nodes]
					gate.fpga_nodeid = #editor.Nodes
					all_gates[gate.id] = gate
				end

				-- determine zoom level (if necessary)
				-- this is useful if all the gates use a nano model so they're far too close to each other to be visible
				local zoom = math.max(1,
					(#plane.gates * FPGANodeSize / (maxx-minx)),
					maxGateHeight / (maxy-miny))

				minx = minx * zoom - GATE_PADDING
				miny = miny * zoom - GATE_PADDING
				maxx = maxx * zoom + GATE_PADDING
				maxy = maxy * zoom + GATE_PADDING

				-- calculate relative direction
				local posx = -plane.pos.x
				local posy = plane.pos.y
				local dist = math.sqrt(posx*posx+posy*posy)
				local posx_norm = posx / dist
				local posy_norm = posy / dist

				-- after getting direction, reset position to center and allow collision detection below to move it out of the way as necessary
				posx = 0
				posy = 0

				-- collision detection
				for k=1,#already_placed do
					local v = already_placed[k]

					if rectanglesIntersect(
						posx+minx-PLANE_PADDING,
						posy+miny-PLANE_PADDING,
						posx+maxx+PLANE_PADDING,
						posy+maxy+PLANE_PADDING,
						
						v.posx+v.minx-PLANE_PADDING,
						v.posy+v.miny-PLANE_PADDING,
						v.posx+v.maxx+PLANE_PADDING,
						v.posy+v.maxy+PLANE_PADDING) then

						posx = posx + posx_norm * ((maxx-minx+PLANE_PADDING)/2 + (v.maxx-v.minx+PLANE_PADDING)/2 + PLANE_PADDING)
						posy = posy + posy_norm * ((maxy-miny+PLANE_PADDING)/2 + (v.maxy-v.miny+PLANE_PADDING)/2 + PLANE_PADDING)
					end
				end

				already_placed[#already_placed+1] = {minx = minx, miny = miny, maxx = maxx, maxy = maxy, posx = posx, posy = posy}

				outputsPosOffset = math.min(outputsPosOffset, miny - PLANE_PADDING * 2)

				-- move gates to new positions
				for _, gate in pairs(plane.gates) do
					gate.fpga_gate.x = -gate.pos.x * zoom + posx
					gate.fpga_gate.y = gate.pos.y * zoom + posy
				end
			end

			local function portNameToNumber(action,name,what)
				what = what or "inputs"
				if not action[what] then return 1 end

				if type(action[what]) == "table" then
					for i=1,#action[what] do
						if action[what][i] == name then return i end
					end
				end

				return 1
			end

			local function getPortType(action,id,what)
				what = what or "inputtypes"
				if not action[what] then return "normal" end
				return action[what][id] or "normal"
			end

			local function getDisplayName(entindex)
				local ent = Entity(entindex)
				if IsValid(ent) then
					local name = ent:GetNWString("WireName")
					if not name or name == "" then
						return ent.PrintName 
					else 
						return name
					end
				end
			end

			local numInputs, numOutputs = 0, 0
			inputsPosOffset = outputsPosOffset - PLANE_PADDING * 2

			-- set up wiring
			for entindex, gate in pairs(all_gates) do
				local action = GateActions[gate.action]
				if not action then continue end

				-- step through all inputs
				if gate.inputs then
					for inputname, input in pairs(gate.inputs) do
						local inputNum = portNameToNumber(action,inputname)
						if not inputNum then continue end

						local target = all_gates[input.src]
						if not target then
							-- no gate found, this is an input arriving from outside fpga
							local typename = string.lower(getPortType(action,inputNum)) .. "-input"
							if not FPGAGateActions[typename] then continue end

							editor:CreateNode({
								type = "fpga",
								gate = typename
							},numInputs * (FPGANodeSize + GATE_PADDING),inputsPosOffset)
							gate.fpga_gate.connections[inputNum] = { #editor.Nodes, 1 }
							numInputs = numInputs + 1
							local node = editor.Nodes[#editor.Nodes]
							local newIoName = getDisplayName(input.src)
							if newIoName and newIoName ~= "" then node.ioName = newIoName .. " " .. numInputs end
						else
							local outputAction = GateActions[target.action]
							if not outputAction then continue end
							local outputNum = portNameToNumber(outputAction,input.name,"outputs")
							gate.fpga_gate.connections[inputNum] = { target.fpga_nodeid, outputNum }
						end
					end
				end

				if gate.outputs then
					-- outputs are always assumed to be leading outside of fpga
					for outputname, output in pairs(gate.outputs) do
						local outputNum = portNameToNumber(action,outputname,"outputs")
						if not outputNum then continue end

						local typename = string.lower(getPortType(action,inputNum,"outputtypes")) .. "-output"
						if not FPGAGateActions[typename] then continue end

						editor:CreateNode({
							type = "fpga",
							gate = typename
						},numOutputs * (FPGANodeSize + GATE_PADDING),outputsPosOffset)
						editor.Nodes[#editor.Nodes].connections[1] = { gate.fpga_nodeid, outputNum }
						numOutputs = numOutputs + 1
					end
				end
			end
		end
	end)

	------------------------------------------------------------------------------
	-- Build tool control panel
	------------------------------------------------------------------------------
	function TOOL.BuildCPanel(panel)
		local currentDirectory
		local FileBrowser = vgui.Create("wire_expression2_browser" , panel)
		panel:AddPanel(FileBrowser)
		FileBrowser:Setup("fpgachip")
		FileBrowser:SetSize(235,400)
		function FileBrowser:OnFileOpen(filepath, newtab)
			if not FPGA_Editor then
				FPGA_Editor = vgui.Create("FPGAEditorFrame")
				FPGA_Editor:Setup("FPGA Editor", "fpgachip")
			end
			FPGA_Editor:Open(filepath, nil, newtab)
		end


		----------------------------------------------------------------------------
		local New = vgui.Create("DButton" , panel)
		panel:AddPanel(New)
		New:SetText("New file")
		New.DoClick = function(button)
			FPGA_OpenEditor()
			FPGA_Editor:AutoSave()
			FPGA_Editor:NewChip(false)
		end
		panel:AddControl("Label", {Text = ""})

		----------------------------------------------------------------------------
		local OpenEditor = vgui.Create("DButton", panel)
		panel:AddPanel(OpenEditor)
		OpenEditor:SetText("Open Editor")
		OpenEditor.DoClick = FPGA_OpenEditor


		----------------------------------------------------------------------------
		panel:AddControl("Label", {Text = ""})
		panel:AddControl("Label", {Text = "FPGA settings:"})


		----------------------------------------------------------------------------
		local modelPanel = WireDermaExts.ModelSelect(panel, "wire_fpga_model", list.Get("Wire_gate_Models"), 5)
		panel:AddControl("Label", {Text = ""})
	end

	------------------------------------------------------------------------------
	-- Tool screen
	------------------------------------------------------------------------------
	tool_program_name = ""
	tool_program_start = 0
	tool_program_size = 0
	tool_program_bytes = ""
	function FPGASetToolInfo(name, size, last_bytes)
		if #name > 18 then
			tool_program_name = name:sub(1,15) .. "..."
		else
			tool_program_name = name
		end
		tool_program_start = math.max(size - 64, 0)
		tool_program_start = tool_program_start - tool_program_start % 8 + 8
		tool_program_size = size
		tool_program_bytes = last_bytes
	end

	local fontTable = {
		font = "Tahoma",
		size = 20,
		weight = 1000,
		antialias = true,
		additive = false,
	}
	surface.CreateFont("FPGAToolScreenAppFont", fontTable)
	fontTable.size = 20
	fontTable.font = "Courier New"
	surface.CreateFont("FPGAToolScreenHexFont", fontTable)
	fontTable.size = 14
	surface.CreateFont("FPGAToolScreenSmallHexFont", fontTable)

	local function drawButton(x, y)
		surface.SetDrawColor(100, 100, 100, 255)
		surface.DrawRect(x, y, 20, 20)
		surface.SetDrawColor(200, 200, 200, 255)
		surface.DrawRect(x, y, 18, 18)
		surface.SetDrawColor(185, 180, 175, 255)
		surface.DrawRect(x+2, y, 16, 18)
	end

	function TOOL:DrawToolScreen(width, height)
		--Background
		surface.SetDrawColor(185, 180, 175, 255)
		surface.DrawRect(0, 0, 256, 256)

		--Top bar
		surface.SetDrawColor(156, 180, 225, 255)
		surface.DrawRect(5, 5, 256-10, 30)
		surface.SetTexture(surface.GetTextureID("gui/gradient"))
		surface.SetDrawColor(31, 45, 130, 255)
		surface.DrawTexturedRect(5, 5, 256-10, 30)

		--App name
		draw.SimpleText("FPGA Editor", "FPGAToolScreenAppFont", 13, 10, Color(255,255,255,255), 0, 0)

		--Buttons
		drawButton(184, 10)
		draw.SimpleText("_", "FPGAToolScreenAppFont", 188, 6, Color(10,10,10,255), 0, 0)
		drawButton(204, 10)
		draw.SimpleText("☐", "FPGAToolScreenAppFont", 205, 8, Color(10,10,10,255), 0, 0)
		drawButton(226, 10)
		draw.SimpleText("x", "FPGAToolScreenAppFont", 231, 7, Color(10,10,10,255), 0, 0)

		--Program name
		draw.SimpleText(tool_program_name, "FPGAToolScreenHexFont", 10, 38, Color(10,10,10,255), 0, 0)
		--Program size
		if tool_program_size < 1024 then
			draw.SimpleText(tool_program_size.."B", "FPGAToolScreenHexFont", 246, 38, Color(50,50,50,255), 2, 0)
		else
			draw.SimpleText(math.floor(tool_program_size/1024).."kB", "FPGAToolScreenHexFont", 246, 38, Color(50,50,50,255), 2, 0)
		end


		--Hex panel
		surface.SetDrawColor(200, 200, 200, 255)
		surface.DrawRect(5, 60, 256-10, 256-65)

		--Hex address
		draw.SimpleText("Offset", "FPGAToolScreenSmallHexFont", 15, 65, Color(0,0,191,255), 0, 0)
		draw.SimpleText("00 01 02 03 04 05 06 07", "FPGAToolScreenSmallHexFont", 75, 65, Color(0,0,191,255), 0, 0)
		local y = 0
		for i=tool_program_start, tool_program_size, 8 do
			draw.SimpleText(string.format(" %04X", i), "FPGAToolScreenSmallHexFont", 15, 82 + y * 20, Color(0,0,191,255), 0, 0)
			y = y + 1
		end

		--Hex data
		for line = 0, 7 do
			local text = ""
			for i=1, 8 do
				local c = string.byte(tool_program_bytes, line * 8 + i)
				if c then
					text = text .. string.format("%02X", c) .. " "
				end
			end
			draw.SimpleText(text, "FPGAToolScreenSmallHexFont", 75, 82 + line * 20, Color(0,0,0,255), 0, 0)
		end

	end
end