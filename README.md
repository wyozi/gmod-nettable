# gmod-nettable

Somewhat efficient but painless table networking for Garry's Mod.

## Features
- ```net.WriteTable``` used by default, but specifying a protocol string to massively reduce payload size is first class supported
- [client] on-demand data requesting (data won't be sent until it is actually needed/requested)
- Only sends changed data
- No table depth limits

## Protocol strings
Protocol strings are a way of specifying what datatypes are sent and in which order. This allows sending only the data instead of numerous headers, type ids and other bloat.

### Constraints
- The data types and their order must be exactly the same on both server and client. Names don't have to be the same on both realms, but should be the same to prevent confusion.
- If a nettable key changes, and the key is not specified in the protocol string, it won't be committed. This can be used to advantage to prevent sending some values to clients, but should not be used as a foolproof security measure.

### Example
A protocol string is simply a space separated string containing data types and the associated key names. For example ```u8:age str:name``` will in the networking phase use an unsigned byte (8-bit integer) for ```age``` key in the nettable and a string for ```name``` key.

### Protocol string data types

Type  | Explanation
------------- | -------------
u8/u16/u32  | 8/16/32 bit unsigned integer
i8/i16/i32  | 8/16/32 bit signed integer
str         | A string
f32         | A float
f64         | A double
[]          | An array (see TODO for an example)
{}          | A subtable (see TODO for an example)

### Subtable/array examples

Protocol string | NetTable structure
-----|------
```{u16:duration str:title}:curmedia```|```curmedia: {duration	=	94, title	=	"Hello world"}```
```[{str:author str:title}]:mediaqueue```|```mediaqueue: { {author = "Mike", title = "Hello"}, {author = "John", title = "World"} }```