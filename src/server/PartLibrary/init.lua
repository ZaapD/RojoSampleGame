local module = {}

function module.NewPart()
    local Part = Instance.new('Part')
    Part.BrickColor = BrickColor.Red()
    Part.Size = Vector3.new(15, 15, 15)
    Part.Anchored = true
    Part.Position = Vector3.new(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100))
    return Part
end

return module;