-- Create the nettable that will hold all our cinema data
local data = nettable.get("CinemaData")
data.cinemas = {}

-- Create a Cinema metatable that will be used for all entries in `cinemas`
local Cinema = {}
Cinema.__index = Cinema

-- We create a helper method to update the nettable with our cinema data
function Cinema:Update()
	nettable.commit(data)
end

-- Playing a video happens by setting a `cur` field in our cinema instance. We could send a net message or whatever as well
function Cinema:Play(url)
	self.cur = {url = url, startTime = CurTime()}
	self:Update()
end

-- Returns how many seconds were elapsed from the start of the video
function Cinema:GetElapsed()
	if not self.cur then return 0 end
	return CurTime() - self.cur.startTime
end

-- Create an API using global functions because that's how cool we are

-- Creates a new Cinema with given id, adds it to nettable and commits it's changes to everyone
function AddCinema(id)
	local ci = setmetatable({}, Cinema)

	data.cinemas[id] = ci
	nettable.commit(data)

	return ci
end

concommand.Add("cctrl_add", function(ply, cmd, args)
	local ci = AddCinema(args[1])

	-- Play some Modeselektor like the hipsters we are
	ci:Play("https://www.youtube.com/watch?v=3YHBFmMMECg")

	timer.Simple(2, function()
		print("Elapsed time hath: ", ci:GetElapsed(), " for video ", ci.cur.url)
	end)
end)
