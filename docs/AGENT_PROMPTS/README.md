# Agent Prompts — Collected GEMINI.md Files

This directory contains the `GEMINI.md` context files used to configure each Antigravity workspace. These are the prompts that define each agent's role, rules, allowed tools, and constraints.

| File | Agent | Antigravity Workspace | Module |
|------|-------|----------------------|--------|
| [ingestion.md](ingestion.md) | Ingestion Agent | `mehfooz-ingestion` | M2 |
| [detection.md](detection.md) | Detection & Reasoning Agent | `mehfooz-detection` | M3 |
| [planning.md](planning.md) | Planning Agent | `mehfooz-planning` | M4 |
| [simulation.md](simulation.md) | Simulation Agent | `mehfooz-simulation` | M5 |
| [orchestrator.md](orchestrator.md) | Orchestrator + Comms Agent | `mehfooz-orchestrator` | M6 |

## Source files

Each prompt file is collected from the agent's directory:

```
agents/ingestion/GEMINI.md   → docs/AGENT_PROMPTS/ingestion.md
agents/detection/GEMINI.md   → docs/AGENT_PROMPTS/detection.md
agents/planning/GEMINI.md    → docs/AGENT_PROMPTS/planning.md
agents/simulation/GEMINI.md  → docs/AGENT_PROMPTS/simulation.md
agents/orchestrator/GEMINI.md → docs/AGENT_PROMPTS/orchestrator.md
```

The root context file (`GEMINI.md` at repo root) applies to all agents and defines shared context: mission, cities, languages, crisis taxonomy, confidence gating, tone rules, and safety constraints.
