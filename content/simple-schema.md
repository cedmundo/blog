---
title: "Introducing Simple Schema"
date: 2025-06-28T15:58:40-06:00
draft: false
---

Simple schema is a programming language with the objetive of helping me generate custom code for data serialization
(using [SDL IO Stream API](https://wiki.libsdl.org/SDL3/CategoryIOStream)), scripting bindings, debug information,
and other tasks commonly used for game development.

The language itself is really simple, this is a snippet of the definition of a Vec2 data type:
```
[[ project = "hello" ]]
module vec2

type Vec2 struct {
  x: float
  y: float
}
```

The generated C code for the definition would be:

```
// hello/vec2.h
#ifndef HELLO_VEC2_H

typedef struct {
  float x;
  float y;
} HELLO_Vec2;

#endif /* HELLO_VEC2_H */
```

However, it will also generate the C code for debug information, data serialization and scripting bindings, for example:

```
// hello/debug/vec2.c

#include <SDL3/SD_iostream.h>

size_t HELLO_DebugVec2(SDL_IOStream *context, HELLO_Vec2 vec2) {
  return SDL_IOprintf(context, "Vec2{x=%.4f y=%.4f}", vec2.x, vec2.y);
}
```

Or, for serialization:
```
// hello/encoding/vec2.c

#include <SDL3/SD_iostream.h>

bool HELLO_WriteVec2(SDL_IOStream *context, HELLO_Vec2 vec2) {
 if (!SDL_WriteU32LE(context, vec2.x)) {
  return false;
 }

 if (!SDL_WriteU32LE(context, vec2.y)) {
  return false;
 }
}
```

And so on...

# Why another schema format?
As the reader may note, the above code share one common feature: the generated code is readable and follows the same conventions as SDL.

That reason lead me to design and build this tool, I want to generate code that is 1. human readable, and 2. uses the same
primitives as SDL3. This way, the result project will be homogeneous and easly extensible without even needing to use this
tool.

For now, I have only worked on the lexer, parser and the generator parts of the code, I'll write a post for each component
in the future. The repository link is [here](https://github.com/cedmundo/SimpleSchema).
