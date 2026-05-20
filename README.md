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

## DALI Agent Code Listing

Below is a condensed view of all four agent types, showing the key reactive rules and message-passing patterns used in the prototype. For the full source, see the files under `scheduling_mas/mas/types/`.

```prolog
%% =============================================================
%% AGENT: alice (patient_type)
%% =============================================================

% Beliefs compiled from ASP baseline (tau_P, tau^S)
appointment(alice, clinicA, docJ, t1).
belief_available(docJ, t1).
intend_consultation(t1).
% Feasibility guard (tau^IC)
can_do_local(Doctor, T) :- belief_available(Doctor, T).

% Reactive rule: disruption triggers belief update + repair
unavailableE(Doctor, T) :>
    retract(belief_available(Doctor, T)),
    assert(belief_unavailable(Doctor, T)),
    attempt_local_repair(T).

% Helper: attempt local repair, else delegate via mediator
attempt_local_repair(T) :-
    (  can_do_local(OtherDoc, T), OtherDoc \= docJ
    -> retract(appointment(alice, clinicA, docJ, T)),
       assert(appointment(alice, clinicA, OtherDoc, T))
    ;  messageA(mediator, send_message(
         request_delegation(alice,clinicA,consultation,T),
         alice), alice)
    ).

% Reactive rule: delegation approved by mediator
delegation_approvedE(Doctor, _FromClinic, T) :>
    retract(appointment(alice, clinicA, _, T)),
    assert(appointment(alice, clinicA, Doctor, T)),
    assert(belief_available(Doctor, T)).

% Reactive rule: consultation completed
consultation_doneE(Doctor, T) :>
    assert(consultation_done(Doctor, T)),
    retract(intend_consultation(T)).

%% =============================================================
%% AGENT: docJ (doctor_clinicA_type)
%% =============================================================

can_do_consultation(docJ, t1).
% Emergency makes doctor unavailable, notifies mediator + patient
emergencyE(Reason) :>
    retract(can_do_consultation(docJ, t1)),
    messageA(mediator, send_message(
      doctor_unavailable(docJ,clinicA,t1,Reason), docJ), docJ),
    messageA(alice, send_message(
      unavailable(docJ, t1), docJ), docJ).

%% =============================================================
%% AGENT: docS (doctor_clinicB_type)
%% =============================================================

can_do_consultation(docS, t1).
% Accept lending request if available
lend_requestE(TargetClinic, _Action, T) :>
    (  can_do_consultation(docS, T)
    -> messageA(mediator, send_message(
         lend_accepted(docS,clinicB,TargetClinic,T),
         docS), docS)
    ;  messageA(mediator, send_message(
         lend_rejected(docS,clinicB,TargetClinic,T),
         docS), docS)
    ).
% Perform consultation after lending approved
perform_consultationE(Patient, T) :>
    messageA(Patient, send_message(
      consultation_done(docS, T), docS), docS).

%% =============================================================
%% AGENT: mediator (mediator_type)
%% =============================================================

group_member(clinicA, docJ).  group_member(clinicB, docS).
available_doctor(docJ, clinicA, t1).
available_doctor(docS, clinicB, t1).
% Disruption notification: update availability
doctor_unavailableE(Doctor, Clinic, T, _Reason) :>
    retract(available_doctor(Doctor, Clinic, T)).
% Delegation request: find doctor in another group
request_delegationE(Patient, Src, Action, T) :>
    find_external_doctor(Src, Action, T).
% Helper: search and send lending request
find_external_doctor(Src, _Action, T) :-
    (  available_doctor(Doc, OtherClinic, T),
       OtherClinic \= Src
    -> messageA(Doc, send_message(
         lend_request(Src, consultation, T),
         mediator), mediator)
    ;  messageA(alice, send_message(
         delegation_failed(T), mediator), mediator)
    ).
% Lending accepted: notify patient, instruct doctor
lend_acceptedE(Doctor, _From, Target, T) :>
    messageA(alice, send_message(
      delegation_approved(Doctor, clinicB, T),
      mediator), mediator),
    messageA(Doctor, send_message(
      perform_consultation(alice, T),
      mediator), mediator).

%% Past events (memory logging)
do_consultationP(docS, t1).
unavailableP(docJ, t1).
```

---

## Supplementary Material

The following sections provide additional detail that was omitted from the paper for space constraints. They are intended to support reproducibility and deeper understanding of the framework.

---

### Hybrid Execution Pipeline (Architecture Diagram)

The overall workflow follows this pipeline:

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         HYBRID EXECUTION PIPELINE                          │
└────────────────────────────────────────────────────────────────────────────┘

 ┌──────────────────┐         ┌─────────────────────────┐
 │  Blueprint       │         │   ASP Solver            │
 │  Personas        │────────▶│   (Global Optimization) │
 │  (patient facts) │         │                         │
 └──────────────────┘         └───────────┬─────────────┘
                                          │
                               Baseline Schedule S
                                          │
                                          ▼
                              ┌───────────────────────┐
                              │   Compilation τ       │
                              │   (ASP → L-DINF)      │
                              └───────────┬───────────┘
                                          │
                          Beliefs, Intentions, Feasibility,
                          Preferences, Group Authorization
                                          │
                                          ▼
                              ┌───────────────────────┐
                              │   L-DINF Runtime Layer│
                              │   (DALI Agents)       │
                              └───────────┬───────────┘
                                          │
                              ┌───────────▼───────────┐
                              │   Disruption Occurs?  │
                              └───┬───────────────┬───┘
                                  │ Yes           │ No
                                  ▼               ▼
                   ┌───────────────────┐    [Normal Execution]
                   │ Local Repair      │
                   │ (feasible action  │
                   │  with max pref)   │
                   └────────┬──────────┘
                            │
                   ┌────────▼─────────┐
                   │ Local repair OK? │
                   └──┬────────────┬──┘
                      │ Yes        │ No
                      ▼            ▼
             [Schedule Updated] ┌───────────────────┐
                                │ Inter-Group       │
                                │ Lending           │
                                │ (lend_G)          │
                                └────────┬──────────┘
                                         │
                                ┌────────▼──────────┐
                                │ Lending OK?       │
                                └──┬────────────┬───┘
                                   │ Yes        │ No
                                   ▼            ▼
                          [Schedule Updated] ┌────────────────────┐
                                             │ Fallback:          │
                                             │ ASP Re-Optimization│
                                             │ (new baseline S')  │
                                             └──────────┬────────┘
                                                        │
                                                        ▼
                                             [Recompile τ, resume]
```

---

### ASP Encoding Details (Blueprint Personas)

The following ASP rules show how persona facts are enriched with inference rules to compute utility values and enforce constraints. These feed into the optimization objective of the ASP solver.

#### Preference Rules

```prolog
% Clinic preference: binary utility for patient-clinic match
clinic_preference_effect(Patient, Clinic, 1) :- preference(Patient, Clinic).
clinic_preference_effect(Patient, Clinic, 0) :- not preference(Patient, Clinic).

% Doctor preference: match on specialization and experience
doctor_preference_effect(Patient, Doctor, 1) :-
    doctor(Doctor, _, _, _, _, Type),
    doctor_experience(Doctor, Specialization, YearsExperience),
    doctor_preference(Patient, Type, Specialization, RequiredYears),
    YearsExperience >= RequiredYears.
```

#### Hard Constraints (Integrity Constraints)

```prolog
% No double-booking: same clinic, doctor, visit type, time
:- appointment(P1, C, D, V, T), appointment(P2, C, D, V, T), P1 != P2.

% Accessibility: disabled patients require accessible clinics
:- disabled(P), appointment(P, C, _, _, _), not accessible(C).

% Clinic budget limits: chronic care costs must not exceed budget
:- chronic_cost(C, Tot), budget(C, B), Tot > B.

% Urgency ordering: higher-urgency patients scheduled first
:- needs(P1, V, U1), needs(P2, V, U2), U1 > U2,
   appointment(P1, _, _, V, T1),
   appointment(P2, _, _, V, T2), T1 > T2.
```

These constraints are compiled by τ^IC into L-DINF feasibility beliefs of the form `B_i(cond → ¬can_do_i(φ_A))`, ensuring they remain enforced during runtime repair.

---

### Model-Theoretic View of the Disruption Scenario

Let φ_A = consultation(t₁). The following traces the state transitions through the L-DINF semantics:

**Initial state M₀:**
```
(M₀, w) ⊨ can_do_docJ(φ_A)
(M₀, w) ⊨ can_do_clinicA(φ_A)
(M₀, w) ⊨ intend_alice(φ_A)
```

**Disruption → M₁** (belief-base update `+¬can_do_docJ(φ_A)`):
```
M₀ ──[+¬can_do_docJ(φ_A)]──▶ M₁

(M₁, w) ⊨ B_alice(¬can_do_docJ(φ_A))
(M₁, w) ⊨ ¬can_do_clinicA(φ_A)      [no local member can do φ_A]
```

**Lending → M₂** (group reconfiguration):
```
Assume: docS ∈ clinicB and (M₁, w) ⊨ can_do_docS(φ_A)
If lending authorization holds:
  (M₁, w) ⊨ lend_clinicA(docS, clinicB, φ_A)

Lending creates M₂ where docS is temporarily authorized for clinicA:
  (M₂, w) ⊨ can_do_clinicA(φ_A)
```

**Execution → M₃** (memory update):
```
(M₃, w) ⊨ do^P_docS(φ_A)
(M₃, w) ⊭ intend_alice(φ_A)          [intention fulfilled and removed]
```

The three operations are:
1. **M₀ → M₁**: Belief-base update (disruption propagation)
2. **M₁ → M₂**: Controlled group reconfiguration (lending)
3. **M₂ → M₃**: Memory update after successful execution

The reasoning remains local: the transition only concerns the affected appointment, the affected clinic group, and the candidate external doctor.

---

### DALI Constructs Used in the Framework

DALI extends Horn-clause logic with constructs for event handling, proactive behavior, and time-sensitive knowledge. The following describes the key features used in this implementation:

#### Event Types

| Suffix | Type | Example | Description |
|--------|------|---------|-------------|
| `E` | External event | `unavailableE(docJ,t1)` | Perceived changes or incoming messages |
| `I` | Internal event | `needVisitI` | Conclusions relevant for deliberation |
| `G` | Goal | `repair_scheduleG` | Internal commitments that expire once achieved |
| `P` | Past event/action | `consultationP(docS,t1)` | Logged items, optionally timestamped |
| `A` | Action | `messageA(...)` | Actions to be executed |

#### Reactive Rules

The central construct is the reactive rule:

```prolog
eventE :> action1A, action2A.
```

When `eventE` occurs, the agent executes `action1A`, `action2A`. Executed actions (suffix `A`) may be recorded as past items (suffix `P`), supporting patterns such as "notify only if not already notified".

#### Beliefs and L-DINF Mental Actions

Beliefs are represented as facts/rules in the agent KB. L-DINF mental actions (`+φ` / `-φ`) are implemented by reactive rules that `assert` or `retract` the corresponding KB facts upon external events. This yields an explicit state progression of the agent's working epistemic state (the current KB snapshot).

#### Feasibility and Preferences

Feasibility predicates compiled from constraints are implemented as guarded rules: `can_do_i(φ_A)` holds when the compiled preconditions are satisfied by the current KB. Preferences compiled from weak constraints are represented as explicit facts or prioritized rules encoding `pref_do_i(φ_A, d)`, enabling the agent to select, among feasible repair actions, one that maximizes the preference degree `d`. For instance:

```prolog
pref_do_i(slot(clinicA, T), 8).
```

#### Groups and Mediated Lending

DALI does not provide native group operators, but supports modular agents and message passing (via `send_message/3`). Group membership and roles are implemented as KB facts:

```prolog
group_member(clinicA, docJ).
group_member(clinicB, docS).
role(clinicA, docJ, doctor).
authorized(clinicA, docJ, consultation).
```

Lending `lend_G(i, H, φ_A)` is realized as a controlled protocol mediated by a dedicated agent: the mediator validates requests, consistently updates membership/authorization facts across agents, and enforces that only same-group agents (or the mediator) can trigger such updates. After reconfiguration, feasibility guards for the delegated action become satisfied at group level, enabling the repair step.

---

## License

Apache License 2.0
