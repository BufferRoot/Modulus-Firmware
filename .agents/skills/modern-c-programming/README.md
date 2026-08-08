# cpp-pro: Senior C++ Development Skill

A comprehensive C++ development skill for AI coding assistants, designed to provide expert-level guidance across all aspects of modern C++ programming.

## Purpose

This skill transforms an AI coding assistant into a **10-year senior Google-level C++ engineer** by combining:

- **Modern C++** (C++11-C++23) expertise
- **Google Style Guide** compliance
- **Professional development workflows**
- **Performance optimization**
- **Cross-platform development**

## Features

### Core Capabilities
- Modern C++ features (lambdas, move semantics, concepts, ranges, coroutines)
- Smart pointers and RAII patterns
- Template metaprogramming
- Google C++ Style Guide enforcement
- Code review and refactoring
- Unit testing best practices

### Specialized Topics
- CUDA/GPU programming
- Embedded systems
- Game engine architecture
- Network programming
- Database integration
- Security best practices

### Tools & Techniques
- xmake build systems (default)
- Debugging (GDB, Valgrind, sanitizers)
- Performance profiling (perf, VTune)
- SIMD and vectorization
- Memory allocation patterns
- Reading complex codebases

## Installation

### For Claude Code CLI

```bash
# Clone the repository
git clone https://github.com/ElCapor/cpp-pro.git

# Or add as a skill (depends on your setup)
# Copy the cpp-pro folder to your skills directory
cp -r cpp-pro ~/.claude/skills/
```

### For OpenCode

```bash
# Clone the repository
git clone https://github.com/ElCapor/cpp-pro.git

# The skill will be automatically available as "cpp-pro"
# Use it by mentioning it in your prompts:
# "Use the cpp-pro skill to help me with..."
```

### For Other AI Agents

If you're integrating this skill into another AI coding assistant:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ElCapor/cpp-pro.git
   ```

2. **Load the skill:** 
   - The main skill is at `cpp-pro/SKILL.md`
   - Reference files are in `cpp-pro/references/`

3. **For AI agents**, add this to your system prompt or context:
   ```
   You have access to the cpp-pro skill for C++ development tasks.
   This skill provides comprehensive guidance on modern C++,
   Google style, xmake builds, debugging, and optimization.
   ```

## Usage

### Triggering the Skill

The skill automatically activates when you ask C++ questions:

- "Help me write a C++ class"
- "Review this C++ code"
- "How do I optimize this algorithm?"
- "Set up a build system for my project"
- Any C++ related task

### Main Skill File

The primary skill file is `SKILL.md` (~1000 lines) containing:
- Quick reference guide
- Core philosophy
- Code examples
- Best practices
- Links to detailed references

### Reference Files

The `references/` directory contains 48 detailed reference files:
- `modern-cpp.md` - Complete modern C++ guide
- `stl.md` - STL containers and algorithms
- `cuda-gpu.md` - GPU programming
- `compilers.md` - GCC, Clang, MSVC differences
- `memory-allocation.md` - Custom allocators
- And many more...

## For AI Agents

When answering C++ questions, you can:

1. **Reference the main skill** for quick answers
2. **Link to specific references** for detailed topics:
   - For templates → `references/templates-metaprogramming.md`
   - For CUDA → `references/cuda-gpu.md`
   - For memory → `references/memory-allocation.md`

3. **Example response:**
   ```
   According to the cpp-pro skill, for this task you should use 
   std::unique_ptr for exclusive ownership. Here's an example:
   
   ```cpp
   auto widget = std::make_unique<Widget>(id);
   ```
   
   For more details, see references/smart-pointers.md
   ```

## Topics Covered

| Category | Topics |
|----------|--------|
| Language | Modern C++11-23, templates, concepts, ranges, coroutines |
| Memory | Smart pointers, RAII, allocators, pools |
| Style | Google C++ Style Guide, naming, formatting |
| Build | xmake, CMake, Conan, vcpkg |
| Concurrency | Threads, atomics, futures, thread pools |
| Systems | CUDA, embedded, Windows API |
| Data | STL, databases, serialization |
| Tools | Debuggers, profilers, sanitizers |
| Architecture | Design patterns, ECS, API design |

## Contributing

This skill is designed to be continuously improved. To contribute:

1. Fork the repository
2. Add or improve reference files
3. Submit a pull request

## License

Apache 2.0 - See LICENSE file for details.

## Links

- GitHub: https://github.com/ElCapor/cpp-pro
- Issues: https://github.com/ElCapor/cpp-pro/issues
