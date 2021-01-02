local Editor = {}

local Nodes = {
  {type = "wire", gate = "floor", x = 0, y = 50, connections = {{3, 1}}},
  {type = "wire", gate = "ceil", x = 0, y = 150, connections = {{3, 2}}},
  {type = "wire", gate = "+", x = 50, y = 100, connections = {{4, 1}}},
  {type = "wire", gate = "exp", x = 150, y = 100, connections = {}}
}

function Editor:Init()
  self.Position = {0, 0}
  self.Zoom = 1
  self.DraggingWorld = false
  self.DraggingGate = nil

  self.DrawingConnection = false
  self.DrawingFromInput = false
  self.DrawingFromOutput = false
  self.DrawingConnectionFrom = nil

  self.LastMousePos = {0, 0}
  self.MouseDown = false

  self.GateSize = 5
  self.IOSize = 1

  self.BackgroundColor = Color(170, 170, 170, 255)
  self.NodeColor = Color(100, 100, 100, 255)
  self.ConnectionColor = Color(255, 255, 255, 255)
  self.InputColor = Color(100, 150, 100, 255)
  self.OutputColor = Color(100, 100, 150, 255)

  --MsgC(Color(0, 150, 255), table.ToString(GateActions, "Gate Actions", true))
end

-- ceil	=	{
--   label	=	function: 0x01eca99bda28,
--   group	=	"Arithmetic",
--   is_banned	=	false,
--   name	=	"Ceiling (Round up)",
--   output	=	function: 0x01eca99bd9f8,
--   inputs	=	{
--       "A",
--       },
--     },



-- UTILITY
function Editor:PosToScr(x, y)
  return self:GetWide()/2 - (self.Position[1] - x) * self.Zoom, self:GetTall()/2 - (self.Position[2] - y) * self.Zoom
end

function Editor:ScrToPos(x, y)
  return self.Position[1] - (self:GetWide()/2 - x) / self.Zoom, self.Position[2] - (self:GetTall()/2 - y) / self.Zoom
end

function Editor:NodeInputPos(node, input)
  return node.x - self.GateSize/2 - self.IOSize, node.y + (input - 1) * self.GateSize
end

function Editor:NodeOutputPos(node, output)
  return node.x + self.GateSize/2, node.y + (output - 1) * self.GateSize
end

-- DETECTION
function Editor:GetNodeAt(x, y)
  local gx, gy = self:ScrToPos(x, y)

  for k, node in pairs(Nodes) do
    if gx < node.x - self.GateSize/2 then continue end
    if gx > node.x + self.GateSize/2 then continue end
    if gy < node.y - self.GateSize/2 then continue end
    if gy > node.y + self.GateSize/2 then continue end

    return k
  end

  return nil
end

function Editor:GetNodeInputAt(x, y)
  local gx, gy = self:ScrToPos(x, y)

  for k, node in pairs(Nodes) do
    gate = GateActions[node.gate]

    if gx < node.x - self.GateSize/2 - self.IOSize then continue end
    if gx > node.x + self.GateSize/2 + self.IOSize then continue end
    if gy < node.y - self.GateSize/2 then continue end
    if gy > node.y - self.GateSize/2 + self.GateSize * table.Count(gate.inputs) then continue end

    for inputNum, input in pairs(gate.inputs) do
      local ix, iy = self:NodeInputPos(node, inputNum)

      if gx < ix - self.IOSize then continue end
      if gx > ix + self.IOSize then continue end
      if gy < iy - self.IOSize then continue end
      if gy > iy + self.IOSize then continue end

      return k, inputNum
    end
  end

  return nil
end

function Editor:GetNodeOutputAt(x, y)
  local gx, gy = self:ScrToPos(x, y)

  for k, node in pairs(Nodes) do
    gate = GateActions[node.gate]

    if gx < node.x - self.GateSize/2 - self.IOSize then continue end
    if gx > node.x + self.GateSize/2 + self.IOSize then continue end
    if gy < node.y - self.GateSize/2 then continue end
    if gy > node.y + self.GateSize/2 then continue end

    local ix, iy = self:NodeOutputPos(node, 1)

    if gx < ix - self.IOSize then continue end
    if gx > ix + self.IOSize then continue end
    if gy < iy - self.IOSize then continue end
    if gy > iy + self.IOSize then continue end

    return k, 1
  end

  return nil
end

-- DRAWING
function Editor:PaintConnection(nodeFrom, output, nodeTo, input)
  local x1, y1 = self:NodeOutputPos(nodeFrom, output)
  local x2, y2 = self:NodeInputPos(nodeTo, input)

  local sx1, sy1 = self:PosToScr(x1, y1)
  local sx2, sy2 = self:PosToScr(x2, y2)

  surface.SetDrawColor(self.ConnectionColor)
  surface.DrawLine(sx1, sy1, sx2, sy2)
end

function Editor:PaintConnections()
  for k1, node in pairs(Nodes) do
    for k2, dest in pairs(node.connections) do
      self:PaintConnection(node, 1, Nodes[dest[1]], dest[2])
    end
  end
end

function Editor:PaintNode(node)
  local gate = GateActions[node.gate]
  local amountOfInputs = table.Count(gate.inputs)

  local x, y = self:PosToScr(node.x, node.y)

  local size = self.Zoom * self.GateSize
  local ioSize = self.Zoom * self.IOSize

  -- Body
  surface.SetDrawColor(self.NodeColor)
  surface.DrawRect(x-size/2, y-size/2, size, size * amountOfInputs)

  -- Name
  surface.SetFont("Default")
  surface.SetTextColor(255, 255, 255)
  local tx, ty = surface.GetTextSize(gate.name)
	surface.SetTextPos(x-tx/2, y-ty/2) 
  surface.DrawText(gate.name)
  
  -- Inputs
  surface.SetDrawColor(self.InputColor)
  for k, input in pairs(gate.inputs) do
    -- This should rely on a function
    surface.DrawRect(x - size/2 - ioSize, y + (k-1) * size, ioSize, ioSize)
  end

  -- Output
  surface.SetDrawColor(self.OutputColor)
  surface.DrawRect(x + size/2, y, ioSize, ioSize)
end

function Editor:PaintNodes()
  for k, node in pairs(Nodes) do
    self:PaintNode(node)
  end
end

function Editor:Paint()
  surface.SetDrawColor(self.BackgroundColor)
  surface.DrawRect(0, 0, self:GetWide(), self:GetTall())

  self:PaintNodes()
  self:PaintConnections()

  self:PaintDebug()

  -- moving the plane
  if self.DraggingWorld then
    local x, y = self:CursorPos()
    local dx, dy = self.LastMousePos[1] - x, self.LastMousePos[2] - y
    self.Position = {self.Position[1] + dx * (1/self.Zoom), self.Position[2] + dy * (1/self.Zoom)}
  end
  -- moving a node
  if self.DraggingNode then
    local x, y = self:CursorPos()
    local gx, gy = self:ScrToPos(x, y)
    Nodes[self.DraggingNode].x = gx
    Nodes[self.DraggingNode].y = gy
  end
  -- drawing a connection
  if self.DrawingConnection then
    local x, y = 0, 0
    if self.DrawingFromInput then
      x, y = self:NodeInputPos(Nodes[self.DrawingConnectionFrom[1]], self.DrawingConnectionFrom[2])
    elseif self.DrawingFromOutput then
      x, y = self:NodeOutputPos(Nodes[self.DrawingConnectionFrom[1]], self.DrawingConnectionFrom[2])
    end
    local sx, sy = self:PosToScr(x, y)
    local mx, my = self:CursorPos()
    surface.SetDrawColor(self.ConnectionColor)
    surface.DrawLine(sx, sy, mx, my)
  end

  local x, y = self:CursorPos()
  self.LastMousePos = {x, y}
end


function Editor:PaintDebug()
  surface.SetFont("Default")
	surface.SetTextColor(255, 255, 255)
	surface.SetTextPos(10, 10) 
  surface.DrawText(self.Position[1] .. ", " .. self.Position[2])
  surface.SetTextPos(10, 30) 
	surface.DrawText(self.Zoom)
end

--ACTIONS
function Editor:BeginDrawingConnection(x, y)
  local node, input = self:GetNodeInputAt(x, y)
  if node then
    --check if something is connected to this input
    local connectedTo = nil
    for nodeId, fromNode in pairs(Nodes) do
      for k, connection in pairs(fromNode.connections) do
        if connection[1] == node && connection[2] == input then
          connectedTo = {nodeId = nodeId, node = fromNode, output = k}
        end
      end
    end

    --Input already connected
    if connectedTo then
      table.remove(connectedTo.node.connections, connectedTo.output)
      self.DrawingConnectionFrom = {connectedTo.nodeId, 1}
      self.DrawingFromOutput = true
    else 
      --input not connected
      self.DrawingConnectionFrom = {node, input}
      self.DrawingFromInput = true
    end
    
    self.DrawingConnection = true
  end

  local node, output = self:GetNodeOutputAt(x, y)
  if node then
    self.DrawingConnection = true
    self.DrawingFromOutput = true
    self.DrawingConnectionFrom = {node, output}
  end
end

--EVENTS
function Editor:OnMousePressed(code)
	if code == MOUSE_LEFT then
    self.MouseDown = true

    local x, y = self:CursorPos()

    --NODE DRAGGING
    local node = self:GetNodeAt(x, y)
    if node then
      self.DraggingNode = node
    end

    --CONNECTION DRAWING
    self:BeginDrawingConnection(x, y)
  elseif code == MOUSE_RIGHT then
    -- PLANE DRAGGING
		self.DraggingWorld = true
	end
end

function Editor:OnMouseReleased(code)
  --if not self.MouseDown  then return end
  local x, y = self:CursorPos()

	if code == MOUSE_LEFT then
    self.MouseDown = false
    self.DraggingNode = nil

    if self.DrawingConnection then
      self:OnDrawConnectionFinished(x, y)
    end
  elseif code == MOUSE_RIGHT then
    self.DraggingWorld = false
  end
  
end

function Editor:OnDrawConnectionFinished(x, y)
  if self.DrawingFromOutput then
    local node, input = self:GetNodeInputAt(x, y)

    if node then
      local sourceNode = Nodes[self.DrawingConnectionFrom[1]]

      table.insert(sourceNode.connections, {node, input})
    end
  elseif self.DrawingFromInput then
    local node, output = self:GetNodeOutputAt(x, y)
    -- discard output for now

    if node then
      local sourceNode = Nodes[node]

      table.insert(sourceNode.connections, {self.DrawingConnectionFrom[1], self.DrawingConnectionFrom[2]})
    end
  end

  self.DrawingConnection = false
  self.DrawingFromInput = false
  self.DrawingFromOutput = false
end

function Editor:OnMouseWheeled(delta)
  self.Zoom = self.Zoom + delta * 0.1
	if self.Zoom < 0.1 then self.Zoom = 0.1 end
	if self.Zoom > 10 then self.Zoom = 10 end
end


vgui.Register("FPGAEditor", Editor, "Panel");