nettableproto = nettableproto or {}

local function curry(f)
	return function (x) return function (y) return f(x,y) end end
end
local function curry_reverse(f)
	return function (y) return function (x) return f(x,y) end end
end

local lshift, rshift, arshift, band, bor, bxor = bit.lshift, bit.rshift, bit.arshift, bit.band, bit.bor, bit.bxor

nettableproto.typeHandlers = {
	["u8"] = { read = curry(net.ReadUInt)(8), write = curry_reverse(net.WriteUInt)(8) },
	["u16"] = { read = curry(net.ReadUInt)(16), write = curry_reverse(net.WriteUInt)(16) },
	["u32"] = { read = curry(net.ReadUInt)(32), write = curry_reverse(net.WriteUInt)(32) },

	["i8"] = { read = curry(net.ReadInt)(8), write = curry_reverse(net.WriteInt)(8) },
	["i16"] = { read = curry(net.ReadInt)(16), write = curry_reverse(net.WriteInt)(16) },
	["i32"] = { read = curry(net.ReadInt)(32), write = curry_reverse(net.WriteInt)(32) },

	-- Variable Length Encoded integer
	["int"] = {
		read = function()
			local ret = 0

			local readBytes = 0
			for i=0,5 do
				readBytes = readBytes + 1

				local b = net.ReadUInt(8)
				ret = bor(ret, lshift(band(b, 0x7F), 7*i))
				if band(b, 0x80) ~= 0x80 then
					break
				end
			end

			nettable.debug("[Type:VarInt] Read ", readBytes, " varint bytes")
			return ret
		end,
		write = function(value)
			local writtenBytes = 1

			while rshift(value, 7) ~= 0 do
				net.WriteUInt(bor(band(value, 0x7F), 0x80), 8)
				value = rshift(value, 7)

				writtenBytes = writtenBytes + 1
			end
			net.WriteUInt(band(value, 0x7F), 8)

			nettable.debug("[Type:VarInt] Wrote ", writtenBytes, " varint bytes")
		end,
	},

	["f32"] = { read = net.ReadFloat, write = net.WriteFloat },
	["f64"] = { read = net.ReadDouble, write = net.WriteDouble },

	["bool"] = { read = net.ReadBool, write = net.WriteBool },

	["array"] = {
		read = function(data)
			local size = nettableproto.typeHandlers.int.read()
			nettable.debug("[Type:Array] Reading array of size ", size)

			local arr = {}
			for i=1,size do
				local key = nettableproto.typeHandlers.int.read()
				local val = data.type.handler.read(data.type.data)

				nettable.debug("[Type:Table] Setting key ", key, " to value of type ", data.type.type)

				arr[key] = val
			end

			return arr
		end,
		write = function(arr, data)
			nettableproto.typeHandlers.int.write(table.Count(arr))

			for k,v in pairs(arr) do
				nettableproto.typeHandlers.int.write(k)
				data.type.handler.write(v, data.type.data)
			end
		end,

		readDeletion = function(data)
			local size = nettableproto.typeHandlers.int.read()
			nettable.debug("[Type:Array-del] Reading keysArray of size ", size)

			local del = {}
			for i=1, size do
				local key = nettableproto.typeHandlers.int.read()
				del[key] = true
			end
			return del
		end,
		writeDeletion = function(del, data)
			nettableproto.typeHandlers.int.write(table.Count(del))

			for k,val in pairs(del) do
				nettableproto.typeHandlers.int.write(k)
				if val ~= true then
					nettable.warn("[Type:Array-del] key ", k, " was not deleted as 'true'!!")
				end
			end

			nettable.debug("[Type:Array-del] Writing keysArray of size ", table.Count(del))
		end,
	},
	["table"] = {
		read = function(data)
			local tbl = {}
			for _,field in ipairs(data.fields) do
				local name = field.name

				local is_provided = net.ReadBool()
				nettable.debug("[Type:Table] Reading ", name, " (provided: ", is_provided, ")")
				if is_provided then
					tbl[name] = field.handler.read(field.data)
				end
			end
			return tbl
		end,
		write = function(tbl, data)
			for _,field in ipairs(data.fields) do
				local name = field.name

				local val = tbl[name]
				local is_provided = val ~= nil

				net.WriteBool(is_provided)
				if is_provided then
					field.handler.write(val, field.data)
				end
			end
		end,

		readDeletion = function(data)
			local bitfield = nettableproto.typeHandlers.int.read()
			nettable.debug("[Type:Table-del] Reading deletedBitfield ", bitfield)

			local del = {}
			for i=1, #data.fields do
				local _bit = lshift(1, i)
				if band(bitfield, _bit) == _bit then
					del[data.fields[i].name] = true
				end
			end
			return del
		end,
		writeDeletion = function(del, data)
			local bitfield = 0

			for i,field in ipairs(data.fields) do
				if del[field.name] then
					bitfield = bor(bitfield, lshift(1, i))
				end
			end

			nettableproto.typeHandlers.int.write(bitfield)
			nettable.debug("[Type:Table-del] Writing deletedBitfield ", bitfield)
		end,
	},

	["str"] = { read = net.ReadString, write = net.WriteString },

	["ply"] = { read = net.ReadEntity, write = net.WriteEntity },
	["ent"] = { read = net.ReadEntity, write = net.WriteEntity },

	["vec"] = { read = net.ReadVector, write = net.WriteVector },
	["ang"] = { read = net.ReadAngle, write = net.WriteAngle },
	["color"] = { read = net.ReadColor, write = net.WriteColor },
}

function nettableproto.compile(str)
	local fields = {}

	local function addtype(typestr, data)
		local handler = nettableproto.typeHandlers[typestr]
		if not handler then
			error("No type handler for type '" .. typestr .. "'")
			return
		end

		local tbl = {
			type = typestr,
			handler = handler,
			data = data
		}

		table.insert(fields, tbl)
	end

	local i = 1
	local function next()
		if i > #str then return false end

		local text = string.sub(str, i)
		local letter = string.sub(text, 1, 1)

		if string.match(letter, "%s") then
			i = i+1
			return true
		end

		if string.match(letter, "%a") then
			local typestr = string.match(text, "([%a%d]+)")

			addtype(typestr)

			i = i+#typestr
			return true
		end

		if letter == "{" then
			local contents = string.sub(string.match(text, "(%b{})"), 2, -2)

			local parsedContents = nettableproto.compile(contents)
			addtype("table", {fields = parsedContents})

			i = i+#contents+2
			return true
		end

		if letter == "[" then
			local contents = string.sub(string.match(text, "(%b[])"), 2, -2)

			local parsedContents = nettableproto.compile(contents)
			if #parsedContents ~= 1 then
				return error("Only arrays with one type are supported!")
			end

			addtype("array", {type = parsedContents[1]})

			i = i+#contents+2
			return true
		end

		if letter == ":" then
			local name = string.match(text, ":(%a+)")

			local lastType = fields[#fields]
			if not lastType then
				return error("Attempting to name a type while none have been created")
			end

			lastType.name = name

			i = i+1+#name
			return true
		end

		error("Invalid char in lexer: '" .. letter .. "'")
	end

	while next() do end

	return fields
end

nettable = nettable or {}
nettable.__tables = nettable.__tables or {}
nettable.__tablemeta = nettable.__tablemeta or {} -- note: stored by table reference instead of id

nettable.__loaded = nettable.__loaded or false
hook.Add("InitPostEntity", "NetTable_SetLoaded", function() nettable.__loaded = true end)

local clr_white = Color(255, 255, 255)
local clr_orange = Color(255, 127, 0)
function nettable.log(...)
	MsgC(clr_white, "[NetTable] ", ...)
end
function nettable.error(err)
	error("[NetTable] " .. tostring(err or "Error"))
end
function nettable.warn(...)
	MsgC(clr_orange, "[NetTable-Warning] ", clr_white, ...)
end

local debug_cvar = CreateConVar("nettable_debug", "0", FCVAR_ARCHIVE)
function nettable.debug(...)
	if not debug_cvar:GetBool() then return end
	print("[NetTable-D] ", ...)
end

-- Nettable ids are always strings, but sending them over and over again over network is expensive.
-- This function can be used to convert the string id into eg. a CRC hash
-- Needs to be same on both client and server
nettable.id_hasher = {
	init = function(id, meta)
		if SERVER then
			util.AddNetworkString(id)
			meta._IdStringtabled = CurTime()
		end
	end,
	hash = function(id)
		return id
	end,

	read = function()
		local is_stringtable = net.ReadBool()

		if is_stringtable then
			local netid = nettableproto.typeHandlers.int.read()
			return util.NetworkIDToString(netid)
		else
			return net.ReadString()
		end
	end,
	write = function(id, meta)
		-- Time elapsed since id was added to stringtables. Used to make sure clients have actually received the string table id
		local elapsed = CurTime() - (meta._IdStringtabled or CurTime())

		if elapsed >= 2 then
			net.WriteBool(true)
			nettableproto.typeHandlers.int.write(util.NetworkStringToID(id))

			nettable.debug("Using stringid to write nettable id")
		else
			net.WriteBool(false)
			net.WriteString(id)

			nettable.debug("NOT Using stringid to write nettable id")
		end
	end,
}
-- Example CRC implementation
--[[
nettable.id_hasher = {
	hash = function(id)
		return tonumber(util.CRC(id))
	end,
	read = function() return net.ReadUInt(64) end,
	write = function(id) net.WriteUInt(id, 64) end,
}
]]

function nettable.resolveIdTblMeta(id)
	local tbl, meta
	if type(id) == "string" then
		id = nettable.id_hasher.hash(id)

		tbl = nettable.__tables[id]
		meta = nettable.__tablemeta[tbl]
	else
		tbl = id
		meta = nettable.__tablemeta[tbl]
		id = meta.id
	end

	return id, tbl, meta
end

function nettable.exists(id)
	id = nettable.id_hasher.hash(id)
	return nettable.__tables[id] ~= nil
end

function nettable.get(id, opts)
	local origId = id

	if not opts or not opts.idHashed then
		id = nettable.id_hasher.hash(id)
	end

	local tbl_existed = true

	-- Create table if doesn't exist
	local tbl = nettable.__tables[id]
	if not tbl then
		-- Don't create if not wanted
		if opts and opts.dontCreate then return nil end

		tbl = {}
		nettable.__tables[id] = tbl

		-- Auto commit functionality
		if SERVER and opts and opts.autoCommit then
			local commitDelay = opts.commitDelay or 0.1
			local function commit()
				if commitDelay <= 0 then
					nettable.commit(id)
				else
					timer.Create("NetTable.AutoCommit." .. id, commitDelay, 0, function()
						nettable.commit(id)
					end)
				end
			end

			local innerTbl = {}
			tbl._values = innerTbl
			setmetatable(tbl, {
				__index = function(t, key) return innerTbl[key] end,
				__newindex = function(t, key, val)
					innerTbl[key] = val
					commit()
				end
			})
		end

		tbl_existed = false
	end

	-- Create tablemeta if doesn't exist
	local meta = nettable.__tablemeta[tbl]
	if not meta then
		meta = {}
		nettable.__tablemeta[tbl] = meta
	end

	if not tbl_existed then
		local initfn = nettable.id_hasher.init
		if initfn then initfn(id, meta) end
	end

	meta.id = id
	meta.origId = origId

	if opts and opts.filter then
		meta.filter = opts.filter
	end

	if opts and opts.proto then
		local compiled = nettableproto.compile(opts.proto)
		meta.proto = compiled
	end

	-- If nettable didn't exist, request a full update from server
	if CLIENT and not tbl_existed then
		local function SendRequest()
			net.Start("nettable_fullupdate") nettable.id_hasher.write(id, meta) net.SendToServer()
		end

		if nettable.__loaded then
			SendRequest()
		else
			hook.Add("InitPostEntity", "NetTable_DeferredRequest:" .. id, SendRequest)
		end

		nettable.debug("Requesting a full update from server for '", id, "'")
	end

	return tbl
end

function nettable.addChangeListener(id, listener)
	local id, tbl, meta = nettable.resolveIdTblMeta(id)

	if not meta then
		return nettable.error("Table '" .. tostring(tbl) .. "' does not have tablemeta. Make sure committed tables are created using nettable.get()")
	end

	meta.changeListeners = meta.changeListeners or {}
	table.insert(meta.changeListeners, listener)
end
function nettable.setChangeListener(id, listenerId, listener)
	local id, tbl, meta = nettable.resolveIdTblMeta(id)

	if not meta then
		return nettable.error("Table '" .. tostring(tbl) .. "' does not have tablemeta. Make sure committed tables are created using nettable.get()")
	end

	meta.changeListeners = meta.changeListeners or {}
	meta.changeListeners[listenerId] = listener
end

function nettable.createChangeEvent(modified, deleted)
	local event = {modified = modified, deleted = deleted}
	return event
end

-- Inspiration from nutscript https://github.com/Chessnut/NutScript/blob/master/gamemode/sh_util.lua#L581
function nettable.computeTableDelta(old, new)
	local out, del = {}, {}

	for k, v in pairs(new) do
		local oldval = old[k]

		if type(v) == "table" and type(oldval) == "table" then
			local out2, del2 = nettable.computeTableDelta(oldval, v)

			for k2,v2 in pairs(out2) do
				out[k] = out[k] or {}
				out[k][k2] = v2
			end
			for k2,v2 in pairs(del2) do
				del[k] = del[k] or {}
				del[k][k2] = v2
			end

		elseif oldval == nil or oldval ~= v then
			out[k] = v
		end
	end

	for k,v in pairs(old) do
		local newval = new[k]

		if type(v) == "table" and type(newval) == "table" then
			local out2, del2 = nettable.computeTableDelta(v, newval)

			for k2,v2 in pairs(out2) do
				out[k] = out[k] or {}
				out[k][k2] = v2
			end
			for k2,v2 in pairs(del2) do
				del[k] = del[k] or {}
				del[k][k2] = v2
			end
		elseif v ~= nil and newval == nil then
			del[k] = true
		end
	end

	return out, del
end

function nettable.deepCopy(tbl)
	local copy = {}

	for k,v in pairs(tbl) do
		if type(v) == "table" then
			v = nettable.deepCopy(v)
		end
		copy[k] = v
	end

	return copy
end

if SERVER then
	util.AddNetworkString("nettable_commit")

	-- Helper function to write payload using net messages
	function nettable.writeNet(id, meta, modified, deleted)
		if meta.proto then
			net.WriteBool(true)

			nettable.debug("Using proto for id '", id, "'")

			for _,field in ipairs(meta.proto) do
				local name = field.name
				local is_modified = modified[name]

				nettable.debug("Proto field '", name,  "' mod status: ", is_modified)

				net.WriteBool(is_modified)
				if is_modified then
					field.handler.write(modified[name], field.data)
				end
			end


			local deleted_bitfield = 0

			-- Deleted fields that have custom deletion handlers
			local deleted_chandlers = {}

			for i,field in ipairs(meta.proto) do
				local name = field.name
				local is_deleted = deleted[name] ~= nil

				if is_deleted then
					nettable.debug("Proto field '", name,  "' is deleted!")
					deleted_bitfield = bor(deleted_bitfield, lshift(1, i))

					-- This field requires custom deletion handling
					if field.handler.writeDeletion then
						table.insert(deleted_chandlers, field)
					end
				end
			end

			nettableproto.typeHandlers.int.write(deleted_bitfield)

			for _,field in ipairs(deleted_chandlers) do
				local name = field.name
				local fully_deleted = deleted[name] == true

				net.WriteBool(fully_deleted)
				if not fully_deleted then
					nettable.debug("Deleting proto field '", name,  "' using custom deletion writer")
					field.handler.writeDeletion(deleted[name], field.data)
				end
			end
		else
			net.WriteBool(false)
			net.WriteTable(modified)
			net.WriteTable(deleted)
		end
	end

	function nettable.commit(id)
		local id, tbl, meta = nettable.resolveIdTblMeta(id)

		if not meta then
			return nettable.error("Table '" .. tostring(tbl) .. "' does not have tablemeta. Make sure committed tables are created using nettable.get()")
		end

		local sent = meta.lastSentTable or {}
		local modified, deleted = nettable.computeTableDelta(sent, tbl)

		if table.Count(modified) == 0 and table.Count(deleted) == 0 then
			nettable.debug("Not committing table; delta was empty")
			return
		end

		nettable.debug("Sending delta tables {mod=", table.ToString(modified), ", del=", table.ToString(deleted), "}")

		local targets
		if meta.filter then
			targets = {}
			for _,p in pairs(player.GetAll()) do
				if meta.filter(p, tbl) then
					targets[#targets+1] = p
				end
			end
		end

		if targets then
			nettable.debug("Nettable sending to filtered plys: ", table.ToString(targets))
		end

		net.Start("nettable_commit")
			nettable.id_hasher.write(id, meta)
			nettable.writeNet(id, meta, modified, deleted)
		if targets then
			net.Send(targets)
		else
			net.Broadcast()
		end

		if meta.changeListeners then
			local changeEvent = nettable.createChangeEvent(modified, deleted)
			for _,l in pairs(meta.changeListeners) do
				l(changeEvent)
			end
		end

		meta.lastSentTable = nettable.deepCopy(tbl)
	end

	util.AddNetworkString("nettable_fullupdate")
	net.Receive("nettable_fullupdate", function(len, cl)
		local id = nettable.id_hasher.read()
		local tbl = nettable.__tables[id]
		if not tbl then
			nettable.warn("User ", cl, " attempted to request inexistent nettable ", id)
			return
		end

		local meta = nettable.__tablemeta[tbl]
		if meta.filter and not meta.filter(cl, tbl) then
			nettable.warn("User ", cl, " attempted to request nettable he's filtered from")
			return
		end

		nettable.debug("Sending full update to ", cl, " for '", id, "'")

		-- We don't want to send uncommitted changes, so we use deep copy of the last sent table
		local modified, deleted = (meta.lastSentTable or {}), {}

		net.Start("nettable_commit")
			nettable.id_hasher.write(id, meta)
			nettable.writeNet(id, meta, modified, deleted)
		net.Send(cl)
	end)
end
if CLIENT then
	net.Receive("nettable_commit", function(len, cl)
		local id = nettable.id_hasher.read()
		nettable.debug("Received commit for '" .. id .. "' (size " .. len .. ")")

		local tbl = nettable.get(id)
		local meta = nettable.__tablemeta[tbl]

		local using_proto = net.ReadBool()

		local mod, del
		if using_proto then
			if not meta.proto then
				nettable.error("using_proto true on a nettable that does not have proto! Make sure you pass a 'proto' to clientside nettable.")
				return
			end

			mod, del = {}, {}

			for _,field in ipairs(meta.proto) do
				local name = field.name
				local is_modified = net.ReadBool()

				if is_modified then
					nettable.debug("Proto field '", name,  "' has been modified")
					mod[name] = field.handler.read(field.data)
				end
			end

			nettable.debug("Proto mod table ", table.ToString(mod))

			-- First read bitfield of deleted fields
			local deletedFields = nettableproto.typeHandlers.int.read()
			nettable.debug("Proto del bitfield ", deletedFields)

			for i,field in ipairs(meta.proto) do
				local _bit = lshift(1, i)
				local is_deleted = band(deletedFields, _bit) == _bit

				-- If it is deleted, then we delegate to relevant deletion handler
				if is_deleted then
					local fully_deleted = true

					if field.handler.readDeletion then
						fully_deleted = net.ReadBool()

						if not fully_deleted then
							nettable.debug("Field '", field.name, "' has been deleted using custom deletion writer")
							del[field.name] = field.handler.readDeletion(field.data)
						end
					end
					
					if fully_deleted then
						nettable.debug("Field '", field.name, "' has been deleted")

						del[field.name] = true
					end
				end
			end
		else
			mod = net.ReadTable()
			del = net.ReadTable()
		end

		local function ApplyMod(mod, t, tid)
			for k,v in pairs(mod) do
				nettable.debug("Applying mod '", k, "=", v, "' to tableid ", tid)
				if type(v) == "table" then
					t[k] = t[k] or {}
					ApplyMod(v, t[k], k)
				else
					t[k] = v
				end
			end
		end
		ApplyMod(mod, tbl, "__main")

		local function ApplyDel(del, t)
			for k,v in pairs(del) do
				if type(v) == "table" then
					t[k] = t[k] or {}
					ApplyDel(v, t[k])
				else
					t[k] = nil
				end
			end
		end
		ApplyDel(del, tbl)

		if meta.changeListeners then
			local changeEvent = nettable.createChangeEvent(mod, del)
			for _,l in pairs(meta.changeListeners) do
				l(changeEvent)
			end
		end

		nettable.debug("Commit applied")
	end)
end