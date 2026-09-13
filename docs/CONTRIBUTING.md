# Contributing to Steel Arena

Thank you for your interest in contributing to Steel Arena! Follow these guidelines to set up your environment, write clean code, and submit pull requests.

---

## 1. Development Environment Setup

1. **Install LÖVE 11.5**:
   - Install from [love2d.org](https://love2d.org) or run `bash tools/fetch-love.sh`.
2. **Clone Repository**:
   ```bash
   git clone https://github.com/your-repo/steel-arena.git
   cd steel-arena
   ```
3. **Run Self-Tests**:
   ```bash
   love src --selftest
   love src --nettest
   ```

---

## 2. Code Style & Standards

- **Lua Version**: Lua 5.1 / LuaJIT compatibility. Do **not** use Lua 5.3+ features like `//` integer division.
- **Indentation**: 2 spaces (no tabs).
- **Naming Conventions**:
  - `CamelCase` for module objects and classes (e.g., `Sim`, `Protocol`, `Audio`).
  - `camelCase` for functions and methods (e.g., `sanitizeLoadout`, `step`).
  - `UPPER_SNAKE` for constants (e.g., `TICK_RATE`, `MAX_ROOMS`).
- **Modularity**:
  - Keep game logic (`game/sim.lua`) strictly separated from client rendering (`render/world.lua`).
  - Keep networking encoders and decoders symmetrical in `net/protocol.lua`.

---

## 3. Testing Requirements

All submissions must pass automated tests:
1. `love src --selftest`: Ensures all modules load cleanly and run AI battle simulations.
2. `love src --nettest`: Verifies end-to-end binary UDP client/server communication.
3. `love src --smoke`: Windowed smoke test confirming menu rendering and loop execution.

---

## 4. Pull Request Workflow

1. Fork the repository and create a feature branch (`git checkout -b feature/my-feature`).
2. Implement your changes and write unit/integration tests where applicable.
3. Run `--selftest` and `--nettest` to ensure zero regressions.
4. Commit with descriptive messages.
5. Push your branch and open a Pull Request.
