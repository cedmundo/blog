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

# Language design

First draft of the language is focused on getting work done, so its kind of bare-bones. Another restriction that
I'm working with, is that there is no planned support for object-oriented code style as first-class citizen, unlike many other
schema formats. This is by design, I don't want to treat data as object, I wish to treat data as data, that's why this
first attempt is going to feel a little bit data-oriented with a hit to [ADTs](https://en.wikipedia.org/wiki/Abstract_data_type).

The generators I'm planning to add are:

* C (C11+SDL3)
  * Type definition (typedefs)
  * Procedure definition (prototypes)
  * Data to string
  * Encode binary data to IOStream
  * Decode binary data from IOStream
  * Encode text data to IOStream
  * Decode text data from IOStream
  * Data validation
  * Push type as lua table
  * GUI Panel introspection (for my custom GUI)
  * Component introspection (for my custom ECS)
* Python, Go, JavaScript
  * Encode binary data to IOStream
  * Decode binary data from IOStream
  * Encode text data to IOStream
  * Decode text data from IOStream
  * Data validation

Features might be added or removed, if so I will post updates.

## Primitives

These are the basic building-blocks that the language will support by default.

```
type bool
type u8
type u16
type u32
type u64

type i8
type i16
type i32
type i64

type float
type double
```

There is no string primitive, In the future I might add it as builtin, but for now,
it must be constructed from primitives.

## Arrays

Aside from primitives, user will have access to standard arrays:

```
u8[3]
float[4]
...
```

The index can actually be a variable, and it can depend on other fields, I'll
explain this further on.

## Type aliases

Useful to generate code which uses static arrays i.e. `float[4]`.

```
type byte u8
type Vec2 float[2]
```

Those will be translated as typeof's in C.

## Structs

Raw c-like structs, aligment and padding can be specified via attributes.

```
type User struct {
  [[ align = 16 ]]
  id: u32
  username: byte[32]
  password: byte[32]
}
```

Also, they are going to be translated as standard C-structures.

## Enums

Raw c-like enums, but better because they are actually type-checked.

```
type Color enum {
  WHITE = 0xFFFFFF
  BLACK = 0x000000
  RED   = 0xFF0000
  BLUE  = 0x00FF00
  GREEN = 0x0000FF
}
```

## Un-tagged unions

Raw c-like enums.

```
type Insect union {
  butterfly: i32
  ladybug: i32
  cricket: float
}
```

It might look like a short-sighted decision for unions, accounting for the tagged-union acceptance in the main stream languages,
however, this unions are intended to be used with more complex structures, such `match`, which will make the user choose
the conditions to use one type or another, effectively getting the same behaviours of a tagged union, except that it will
be more flexible.

## Procedure prototypes

Will be translated as standard C prototypes.

```
proc add(a: i32, b: i32) -> i32
```

## What about dynamic data?

Up to the last example, I have not provided any mechanisms to write dynamic data reading, such strings or variable-size arrays,
this is because the schema expects you to describe how to read and write the data of the type, within the type. Let me explain:

```
type String struct {
  length: u16
  data: byte[length]
}
```

In the example above, I'm defining a string as a structure of two components: a length and a byte array, which contains the data.
This will help the generator understand the relationships between the data and it will generate the proper code to read or write
the binary contents (i.e.):

```
bool BDF_ReadString(IOStream *stream, BDF_String *bdf_string) {
  if (!SDL_ReadU16BE(stream, &bdf_string->length)) {
    return false;
  }

  bd_string->data = SDL_malloc(sizeof(BD_Byte) * bdf_string->length);
  if (bd_string->data == NULL) {
    return false;
  }

  if (SDL_ReadIO(stream, bd_string->data, bdf_string->length) != bdf_string->length) {
    return false;
  }

  return true;
}
```

And it is only possible to do it because the data relationship is described in the schema itself.

As more seasoned developers might be able to stop, the last implementation of string is kind of bad, because it really doesn't
account of unicode strings, (it can actually do it if we process it as a BLOB, which can work with UTF-8), but if we would be
a little bit more restrictive, we can write a UTF-16 string:

```
type StringUTF16 struct {
  rune_count: u16
  runes: u16[rune_count * 4]
}
```

This way, we can actually describe the data itself and its relationship, and automate the data serialization on the way.

## What about tagged-unions?

In previous section, I defined the unions as untagged, the reason is that they will work the same way as arrays:

```
type FigureType enum {
  CIRCLE
  SQUARE
  RECTANGLE
}

type Circle struct {
  radius: float
}

type Square struct {
  side: float
}

type Rectangle struct {
  width: float
  height: float
}

type SupportedFigure union {
  Circle
  Square
  Rectangle
}

type Figure struct {
  figure_type: FigureType
  figure: SupportedFigure match(figure_type) {
    case CIRCLE => Circle
    case SQUARE => Square
    case RECTANGLE => Rectangle
    default => error("unknown figure type!")
  }
}
```

As we can see, we are not only describing the data structure, but also the relationship between `figure_type` and `figure`,
meaning that the encoder and decoder will be capable of choosing (and thus, validating) the correct union element for
the given `figure_type`, this is incredibly powerful, since the union won't depend on an opinionanted implementation, instead
it will just depend on the data itself.

But this last feature is not a priority, so it might not be added in the first version of the format.

# Why another schema format?
As the reader may note, the above code share one common feature: the generated code is readable and follows the same conventions as SDL.

That reason lead me to design and build this tool, I want to generate code that is 1. human readable, and 2. uses the same
primitives as SDL3. This way, the result project will be homogeneous and easly extensible without even needing to use this
tool.

For now, I have only worked on the lexer, parser and the generator parts of the code, I'll write a post for each component
in the future. The repository link is [here](https://github.com/cedmundo/SimpleSchema).
