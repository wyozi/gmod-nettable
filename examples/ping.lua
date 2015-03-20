local t = nettable.get("pings", {proto = "f32:time ply:user"})

if SERVER then
	concommand.Add("svping", function(ply)
		t.time = CurTime()
		t.user = ply
		nettable.commit(t)
	end)
	concommand.Add("clrping", function(ply)
		t.time = nil
		t.user = nil
		nettable.commit(t)
	end)
end
if CLIENT then
	hook.Add("HUDPaint", "Test", function()
		draw.SimpleText(string.format("Last ping by %s at %f", (IsValid(t.user) and t.user:Nick() or "NULL"), t.time or -1), "DermaLarge", 100, 100)
	end)
end