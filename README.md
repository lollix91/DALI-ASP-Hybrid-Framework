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

## License

Apache License 2.0
