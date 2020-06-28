# LGNC — LGN Contracts

## About
LGNC is a simple yet powerful tool for building services. The general idea is you define your services and contracts in YAML format
(please refer to specification for more in-depth details), then you generate a codebase for target platform (in this case, Swift)
and it does all the boring stuff for you, like request validation. But most importantly, it would never let you to respond with
an invalid response.

Originally LGNC was developed for internal services communication (game backend, to be more specific), and the priority was
to make it real fast and compact. Therefore a dedicated protocol has been developed — LGNP[rotocol] with a respective server —
LGNS[erver]. You may call LGNP an abridged version of HTTP, if you wish. LGNS (hence LGNP) is a first class citizen in LGNC
ecosystem.

HOWEVER. Let me dispel your concerns with this: LGNC does support HTTP transport, but with some limitations:
* it's always `POST` method
* [almost] no headers
* no basic auth
* no cookies
* no URL params (data is always sent in body as JSON or MsgPack)
* SSL must be terminated on reverse-proxy level (nginx etc.)

## Usage
This document will not cover the LGNC schema format specification. Instead, let's focus on Swift API usage.

## FAQ
### Why not OpenAPI/Swagger? How is it different?
OpenAPI is a total overkill for 99% of web applications, including quite complicated ones. From my personal experience, I've never yet
worked on a project that wouldn't be a hundred percent satisfied with current (pre-release) LGNC featureset.

Don't get me wrong, OpenAPI is a great and mature tool, but it's just too much, and you can't really use the bare minimum of it while
preserving the acceptable level of readability of schemas (manifestos, you name it). LGNC, on the other hand, does precisely that:
it's ultra laconic and offers THE featureset you will ever need both in your pet-projects and real-world production systems.

Of course, you may find it lacking certain features here and there, but this is what I meant earlier: you just entered that 1%
that wouldn't be satisfied by LGNC. And TBH it's totally not what we aim for: we can't and we won't [ever be able to] completely
satisfy everyone.

### Still don't get it. Is it better than gRPC then?
Here is a flashback. I started building LGNC (and LGNKit in general) back in 2015, when Swift went opensource. For obvious reasons,
there wasn't anything at all yet at that time. When we got gRPC/OpenAPI for Swift, it was way too late for me :)

I'm not saying that it's better than gRPC or OpenAPI, I'm trying to say that it does everything I need it to do, no more, no less. This is what
makes it better _personally_ for me.
