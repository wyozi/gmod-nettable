nettableproto = {}

local function curry(f)
	return function (x) return function (y) return f(x,y) end end
end
local function curry_reverse(f)
	return function (y) return function (x) return f(x,y) end end
end

local type_handlers = {
	["u8"] = { read = curry(net.ReadUInt)(8), write = curry_reverse(net.WriteUInt)(8) },
	["u16"] = { read = curry(net.ReadUInt)(16), write = curry_reverse(net.WriteUInt)(16) },
	["u32"] = { read = curry(net.ReadUInt)(32), write = curry_reverse(net.WriteUInt)(32) },

	["i8"] = { read = curry(net.ReadInt)(8), write = curry_reverse(net.WriteInt)(8) },
	["i16"] = { read = curry(net.ReadInt)(16), write = curry_reverse(net.WriteInt)(16) },
	["i32"] = { read = curry(net.ReadInt)(32), write = curry_reverse(net.WriteInt)(32) },

	["f32"] = { read = net.ReadFloat, write = net.WriteFloat },
	["f64"] = { read = net.ReadDouble, write = net.WriteDouble },

	["array"] = {
		read = function(data)
			local size = net.ReadUInt(16)
			nettable.debug("[Type:Array] Reading array of size ", size)

			local arr = {}
			for i=1,size do
				local key = net.ReadInt(32)
				local val = data.type.handler.read(data.type.data)

				nettable.debug("[Type:Table] Setting key ", key, " to value of type ", data.type.type)

				arr[key] = val
			end

			return arr
		end,
		write = function(arr, data)
			net.WriteUInt(table.Count(arr), 16)

			for k,v in pairs(arr) do
				net.WriteInt(k, 32)
				data.type.handler.write(v, data.type.data)
			end
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
	},

	["str"] = { read = net.ReadString, write = net.WriteString },

	["ply"] = { read = net.ReadEntity, write = net.WriteEntity },
	["ent"] = { read = net.ReadEntity, write = net.WriteEntity },
}

function nettableproto.compile(str)
	local fields = {}

	local function addtype(typestr, data)
		local handler = type_handlers[typestr]
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

--[[
{u16:duration str:title}:curmedia
[{str:url ply:adder}]:mediaqueue
]]

nettable = nettable or {}
nettable.__tables = nettable.__tables or {}
nettable.__tablemeta = nettable.__tablemeta or {} -- note: stored by table reference instead of id

local clr_white = Color(255, 255, 255)
local clr_orange = Color(255, 127, 0)
function nettable.log(...)
	MsgC(clr_white, "[NetTable] ", ...)
end
function nettable.error(err)
	error("[NetTable] " .. tostring(err or "Error"))
end
function nettable.warn(...)
	MsgC(clr_orange, "[NetTable] ", clr_white, ...)
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
	hash = function(id)
		return id
	end,
	read = net.ReadString,
	write = net.WriteString,
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

function nettable.get(id, opts)
	local origId = id

	if not opts or not opts.idHashed then
		id = nettable.id_hasher.hash(id)
	end

	local tbl_existed = true

	-- Create table if doesn't exist
	local tbl = nettable.__tables[id]
	if not tbl then
		tbl = {}
		nettable.__tables[id] = tbl

		tbl_existed = false
	end

	-- Create tablemeta if doesn't exist
	local meta = nettable.__tablemeta[tbl]
	if not meta then
		meta = {}
		nettable.__tablemeta[tbl] = meta
	end

	meta.id = id
	meta.origId = origId

	if opts and opts.proto then
		local compiled = nettableproto.compile(opts.proto)
		meta.proto = compiled
	end

	if CLIENT then
		-- If didn't exist, request a full update from server
		if not tbl_existed then
			net.Start("nettable_fullupdate") nettable.id_hasher.write(id) net.SendToServer()
		end
	end

	return tbl
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

function nettable.commit(id)
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

	if not meta then
		return nettable.error("Table '" .. tostring(tbl) .. "' does not have tablemeta. Make sure committed tables are created using nettable.get()")
	end

	local sent = meta.lastSentTable or {}
	local modified, deleted = nettable.computeTableDelta(sent, tbl)

	if table.Count(modified) == 0 and table.Count(deleted) == 0 then
		nettable.debug("Not committing table; delta was empty")
		return
	end

	local function NetWrite()
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

			for i,field in ipairs(meta.proto) do
				local name = field.name
				local is_deleted = deleted[name]

				if is_deleted then
					nettable.debug("Proto field '", name,  "' is deleted!")
					deleted_bitfield = bit.bor(deleted_bitfield, bit.lshift(1, i))
				end
			end

			net.WriteUInt(deleted_bitfield, 16)

			nettable.debug("Deleted bitfield: ", deleted_bitfield)
		else
			net.WriteBool(false)
			net.WriteTable(modified)
			net.WriteTable(deleted)
		end
	end

	nettable.debug("Sending delta tables {mod=", table.ToString(modified), ", del=", table.ToString(deleted), "}")

	net.Start("nettable_commit")
		nettable.id_hasher.write(id)
		NetWrite()
	net.Broadcast()

	meta.lastSentTable = nettable.deepCopy(tbl)
end

if SERVER then
	util.AddNetworkString("nettable_commit")
	util.AddNetworkString("nettable_fullupdate")

	net.Receive("nettable_fullupdate", function(len, cl)
		local id = nettable.id_hasher.read()
		local tbl = nettable.__tables[id]
		if not tbl then
			nettable.warn("User ", cl, " attempted to request inexistent nettable ", id)
			return
		end

		local modified, deleted = nettable.computeTableDelta({}, tbl)

		net.Start("nettable_commit")
			nettable.id_hasher.write(id)
			net.WriteBool(false)
			net.WriteTable(modified)
			net.WriteTable(deleted)
		net.Broadcast()
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

			local deleted_bitfield = net.ReadUInt(16)
			nettable.debug("Received proto del bitfield ", deleted_bitfield)

			for i=1,16 do
				local b = bit.lshift(1, i)
				if bit.band(deleted_bitfield, b) == b then
					nettable.debug("Field #", b, " has been deleted")

					local field = meta.proto[i]
					if field then del[field.name] = true end
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

		nettable.debug("Commit applied")
	end)
end