# Entita

## About
This module is a simple low-level _activerecord-ish_ framework. It's heavily utilized in LGNC module as a foundation for validating/unpacking of request/response entities, as well as for further packing.

Entita isn't in charge of actual data conversion from/to string/bytes (JSON, MsgPack etc). Instead, it requires `Entita.Dict` as input which is just a typealias for `[String: Any]` dictionary, which can hold anything within that `Any`.

## FAQ

**Q**: Why not `Codable`?
**A**: There can be more than one error during entity unpacking, throwing an exception at first error isn't really user-friendly, whilist LGNC would like to do precisely that. This tool allows to solve that problem. However, I will abandon this library the day Apple adds multi-error support to `Codable`.

**Q**: Should I use Entita in my project?
**A**: Not really. Unless you want to contribute to Entita itself or LGNC in general, you shouldn't really bother diving into Entita. That's why there aren't actual docs on this module. 

**Q**: Why "entita"? What does that mean?
**A**: "Entita" is translated as "object" in Italian. And it's also a bird in Swedish (poecile palustris).
