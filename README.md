# DALI-ASP Hybrid Framework

> Prototype implementation for: *"From Constraints to Cognition: A Hybrid Framework for Adaptive, Explainable Scheduling"*

This repository contains a working multi-agent system (MAS) implemented in [DALI](https://github.com/AAAI-DISIM-UnivAQ/DALI) that demonstrates the hybrid ASP/L-DINF scheduling architecture described in the paper. The system shows how runtime disruptions in a healthcare scheduling scenario are handled through belief update, local repair, preference-guided action selection, and inter-group delegation.

---

## Architecture

The MAS consists of four agents implementing the L-DINF cognitive layer:

| Agent | Role | L-DINF Concepts |
|-------|------|----------------|
| `alice` | Patient | B_i, intend_i, can_do_i, belief update |
| `docJ` | Doctor (clinicA) | B_i, can_do_i, disruption source |
| `docS` | Doctor (clinicB) | B_i, can_do_i, lending acceptance |
| `mediator` | Delegation Manager | lend_G, group membership, explanation trace |

## Scenario

The system demonstrates the following execution flow:

1. **Baseline Schedule** (from ASP): `appointment(alice, clinicA, docJ, t1)`
2. **Disruption**: Dr. Jones (docJ) becomes unavailable due to emergency
3. **Belief Update**: `[clinicA: +neg(can_do_docJ(consultation(t1)))]`
4. **Local Repair Attempt**: Alice checks for other doctors in clinicA → fails
5. **Cross-Group Delegation**: Mediator finds docS in clinicB, initiates `lend_clinicA(docS, clinicB, consultation(t1))`
6. **Resolution**: docS performs consultation, Alice's schedule updated
7. **Explanation Trace**: Full log of reasoning steps produced

---

## Prerequisites

- **SICStus Prolog** (4.6.0+) installed and in PATH
- **DALI** framework in the sibling directory (`../DALI/`)

## Running

```bat
cd scheduling_mas
startmas.bat
```

### Triggering the Disruption Scenario

Once the MAS is running, use the **User Console**:

```prolog
% Step 1: Target docJ and trigger emergency
docJ.
user.
send_message(emergency(urgent_call), user).
```

This triggers the full cascade:
- docJ notifies mediator and alice of unavailability
- Alice attempts local repair (fails)
- Alice requests delegation from mediator
- Mediator finds docS, sends lending request
- docS accepts, performs consultation
- Alice receives confirmation, schedule updated

### Querying Agent Status

```prolog
alice.
user.
send_message(status, user).
```

### Viewing Explanation Trace

```prolog
mediator.
user.
send_message(print_trace, user).
```

---

## Project Structure

```
scheduling_mas/
├── startmas.bat                  # MAS launcher
├── conf/
│   ├── communication.con         # FIPA communication rules
│   ├── makeconf.bat              # Agent configuration generator
│   ├── startagent.bat            # Individual agent starter
│   └── mas/                      # Generated configs (runtime)
├── mas/
│   ├── types/
│   │   ├── patient_type.txt      # Alice: beliefs, intentions, repair logic
│   │   ├── doctor_clinicA_type.txt  # docJ: availability, disruption
│   │   ├── doctor_clinicB_type.txt  # docS: lending, consultation
│   │   └── mediator_type.txt     # Delegation protocol, trace logging
│   └── instances/
│       ├── alice.txt             # → patient_type
│       ├── docJ.txt              # → doctor_clinicA_type
│       ├── docS.txt              # → doctor_clinicB_type
│       └── mediator.txt          # → mediator_type
├── build/                        # Generated agent files (runtime)
├── work/                         # Runtime agent copies
└── log/                          # Execution logs
```

---

## L-DINF to DALI Mapping (implemented)

| L-DINF Construct | DALI Implementation |
|-----------------|-------------------|
| `B_i(φ)` | Dynamic fact in agent KB (`assert`/`retract`) |
| `intend_i(φ_A)` | `intend_consultation(T)` fact + goal-driven rules |
| `can_do_i(φ_A)` | Guarded rule `can_do_local(Doctor, T)` |
| `pref_do_i(φ_A, d)` | Preference facts (extensible) |
| `[G:+φ]` | Reactive rule on `unavailableE` → `retract` + `assert` |
| `lend_G(i, H, φ_A)` | Mediated message protocol via `mediator` agent |

---

## References

- S. Costantini, V. Pitoni, A. Formisano, L. De Lauretis. *From Constraints to Cognition: A Hybrid Framework for Adaptive, Explainable Scheduling.* LOPSTR 2026.
- [DALI Framework](https://github.com/AAAI-DISIM-UnivAQ/DALI)

---

## License

Apache License 2.0
