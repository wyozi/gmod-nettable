local t = nettable.get("shoutbox", _, {proto = "[{str:msg ply:ply}]:msgs"})
if SERVER then
	concommand.Add("shout", function(ply, _, _, raw)
		t.msgs = t.msgs or {}
		table.insert(t.msgs, {ply = ply, msg = raw})
		nettable.commit(t)
	end)
end
if CLIENT then
	hook.Add("HUDPaint", "Test", function()
		for i,v in pairs(t.msgs or {}) do
			local clr, name = Color(127, 127, 127), "NULL"
			if IsValid(v.ply) then
				clr = team.GetColor(v.ply)
				name = v.ply:Nick()
			end
			
			draw.SimpleText(name .. ":", "DermaDefaultBold", 10, 100 + i*15, clr)
			draw.SimpleText(v.msg, "DermaDefaultBold", 150, 100 + i*15)
		end
	end)
end