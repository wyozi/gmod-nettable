# gmod-nettable

Somewhat efficient but painless table networking for Garry's Mod.

## Features
- Nettables are identified by a string id on server and client
- ```net.WriteTable``` used by default, but specifying a protocol string to massively reduce payload size is first class supported
- on-demand data requesting (no need to mess with _PlayerInitSpawn_ hook, data is sent automatically when client first requests it)
- Only sends changed data (using a table delta algorithm)
- No table depth limits

## Commented example
```lua
-- Creates a reference to 'shoutboxs' nettable on both CLIENT and SERVER. Nettables with same IDs are
--    connected over the network.
-- 
-- 'proto' string is used to make nettable send binary data instead of slightly inefficient net.WriteTable
--    it is optional, so this example would work just as fine if the 'proto' string was removed
--
--    Note: this example stores shouts in 'msgs' subtable instead of the nettable itself,
--    because protocol strings do not currently support the whole nettable as an array.
--    If 'proto' was removed, you could store shouts directly in the nettable.
local t = nettable.get("shoutboxs", {proto = "[str]:msgs"})

if SERVER then
	concommand.Add("shouts", function(ply, _, _, raw)
		-- Nettable is internally a normal table, so you can use table functions on it
		t.msgs = t.msgs or {}
		table.insert(t.msgs, raw)

		-- Calling 'commit' sends updates to all players if no 'filter' is specified
		nettable.commit(t)
	end)
end
if CLIENT then
	hook.Add("HUDPaint", "Test", function()
		-- Again, nettable is a normal table so it (or its subtable) can be iterated normally
		for i,v in pairs(t.msgs or {}) do
			draw.SimpleText(v, "DermaDefaultBold", 100, 100 + i*15)
		end
	end)
end
```

See ![examples](examples/) for more examples.

## Filters
If specific nettable's data should only be sent to some players, you can pass a filter function in ```opts``` to ```nettable.get```.
```lua
local secretTable = nettable.get("secret", {filter = function(ply) return ply:IsSuperAdmin() end})
secretTable.password = "hunter2"
nettable.commit("secret")
```

## Protocol strings
Protocol strings are a way of specifying what datatypes are sent and in which order. This allows sending only the data instead of numerous headers, type ids and other bloat.

### Constraints
- The data types and their order must be exactly the same on both server and client. Names don't have to be the same on both realms, but should be the same to prevent confusion.
- If a nettable key changes, and the key is not specified in the protocol string, it won't be committed. This can be used to advantage to prevent sending some values to clients, but should not be used as a foolproof security measure.

### Example
A protocol string is a space separated string containing data types and the associated key names.

Following table assumes that a nettable is defined as ```local nt = nettable.get("test")```  

Protocol string | NetTable structure
-----|------
```u8:age str:name``` | an unsigned byte for ```nt.age``` and a string for ```nt.name```.
```{f32:duration str:title}:curmedia``` | a float for ```nt.curmedia.duration``` and a string for ```nt.curmedia.title```
```[{str:author str:title}]:mediaqueue``` | for each entry in ```nt.mediaqueue``` array: a string for ```author``` and for ```title```

### Protocol string data types

Type  | Explanation
------------- | -------------
u8/u16/u32  | 8/16/32 bit unsigned integer
i8/i16/i32  | 8/16/32 bit signed integer
str         | A string
f32         | A float
f64         | A double
[]          | An array
{}          | A subtable
ply         | A GMod Player
ent         | A GMod Entity