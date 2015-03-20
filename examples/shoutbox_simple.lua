local t = nettable.get("shoutboxs", _, {proto = "[str]:msgs"})

if SERVER then
	concommand.Add("shouts", function(ply, _, _, raw)
		t.msgs = t.msgs or {}
		table.insert(t.msgs, raw)
		nettable.commit(t)
	end)
end
if CLIENT then
	hook.Add("HUDPaint", "Test", function()
		for i,v in pairs(t.msgs or {}) do
			draw.SimpleText(v, "DermaDefaultBold", 100, 100 + i*15)
		end
	end)
end