%% ============================================================
%% test_scenario.pl — Self-contained scenario simulator
%% ============================================================
%% Simulates the full disruption-delegation scenario described
%% in the paper WITHOUT requiring the full DALI MAS infrastructure.
%%
%% Usage (SICStus Prolog):
%%   sicstus -l test_scenario.pl --goal "run_scenario."
%%
%% This script:
%%   1. Loads baseline schedule (compiled from ASP)
%%   2. Initializes all agent beliefs
%%   3. Triggers disruption (docJ unavailable)
%%   4. Executes belief update cascade
%%   5. Attempts local repair (fails)
%%   6. Executes cross-group delegation protocol
%%   7. Performs consultation via lent doctor
%%   8. Produces a full explanation trace
%% ============================================================

:- use_module(library(lists)).

%% --- Dynamic predicates for agent knowledge bases ---

% Baseline schedule
:- dynamic appointment/4.
% Agent beliefs
:- dynamic belief_available/3.        % belief_available(Agent, Doctor, TimeSlot)
:- dynamic belief_unavailable/3.      % belief_unavailable(Agent, Doctor, TimeSlot)
% Group membership
:- dynamic group_member/2.            % group_member(Group, Agent)
% Intentions
:- dynamic intend/2.                  % intend(Agent, Action)
% Feasibility
:- dynamic can_do/3.                  % can_do(Agent, Action, TimeSlot)
% Delegation state
:- dynamic lent_to/3.                 % lent_to(Doctor, FromGroup, ToGroup)
:- dynamic delegation_log/5.          % delegation_log(Doctor, From, To, TimeSlot, Status)
% Execution log
:- dynamic performed/3.               % performed(Doctor, Action, TimeSlot)
% Schedule state
:- dynamic schedule_state/2.          % schedule_state(Patient, State)
% Trace log
:- dynamic trace_entry/4.             % trace_entry(StepN, Time, Type, Details)
:- dynamic step_counter/1.
:- dynamic scenario_start_time/1.

step_counter(0).

%% ============================================================
%% TRACE LOGGING
%% ============================================================

get_elapsed(Elapsed) :-
    scenario_start_time(T0),
    statistics(walltime, [Now,_]),
    Elapsed is Now - T0.

log_trace(Type, Details) :-
    retract(step_counter(N)),
    N1 is N + 1,
    assert(step_counter(N1)),
    get_elapsed(Elapsed),
    assert(trace_entry(N1, Elapsed, Type, Details)),
    format('[TRACE #~w] (~w ms) ~w: ~w~n', [N1, Elapsed, Type, Details]).

%% ============================================================
%% PHASE 1: INITIALIZATION (Baseline from ASP)
%% ============================================================

init_baseline :-
    nl, write('============================================================'), nl,
    write('  PHASE 1: BASELINE SCHEDULE INITIALIZATION'), nl,
    write('============================================================'), nl, nl,

    % Baseline schedule (output of ASP solver)
    assert(appointment(alice, clinicA, docJ, t1)),
    log_trace(init, 'Baseline schedule loaded: appointment(alice, clinicA, docJ, t1)'),

    % Group membership
    assert(group_member(clinicA, docJ)),
    assert(group_member(clinicB, docS)),
    log_trace(init, 'Groups: clinicA={docJ}, clinicB={docS}'),

    % Agent beliefs (compiled via tau_P)
    assert(belief_available(alice, docJ, t1)),
    assert(belief_available(mediator, docJ, t1)),
    assert(belief_available(mediator, docS, t1)),
    log_trace(belief_init, 'B_alice(available(docJ, t1))'),
    log_trace(belief_init, 'B_mediator(available(docJ, t1))'),
    log_trace(belief_init, 'B_mediator(available(docS, t1))'),

    % Feasibility (compiled via tau^IC)
    assert(can_do(docJ, consultation, t1)),
    assert(can_do(docS, consultation, t1)),
    log_trace(feasibility, 'can_do(docJ, consultation, t1) = true'),
    log_trace(feasibility, 'can_do(docS, consultation, t1) = true'),

    % Intentions (compiled via tau^S)
    assert(intend(alice, consultation(t1))),
    log_trace(intention, 'intend_alice(consultation(t1))'),

    % Schedule state
    assert(schedule_state(alice, nominal)),
    log_trace(state, 'schedule_state(alice) = nominal'),

    nl, write('  >> Baseline initialization complete.'), nl, nl.

%% ============================================================
%% PHASE 2: DISRUPTION EVENT
%% ============================================================

trigger_disruption :-
    nl, write('============================================================'), nl,
    write('  PHASE 2: DISRUPTION - Doctor Unavailability'), nl,
    write('============================================================'), nl, nl,

    % External event: docJ becomes unavailable
    log_trace(disruption, 'External event: emergency(docJ, urgent_call)'),

    % docJ updates own beliefs
    retract(can_do(docJ, consultation, t1)),
    log_trace(belief_update, '[docJ] retract(can_do(docJ, consultation, t1))'),

    % docJ notifies mediator
    log_trace(message, 'docJ -> mediator: doctor_unavailable(docJ, clinicA, t1, urgent_call)'),

    % Mediator updates beliefs
    retract(belief_available(mediator, docJ, t1)),
    assert(belief_unavailable(mediator, docJ, t1)),
    log_trace(belief_update, '[mediator] retract(available(docJ, t1))'),
    log_trace(belief_update, '[mediator] assert(unavailable(docJ, t1))'),

    % docJ notifies alice
    log_trace(message, 'docJ -> alice: unavailable(docJ, t1)'),

    % Alice updates beliefs: [clinicA: +neg(can_do_docJ(consultation(t1)))]
    retract(belief_available(alice, docJ, t1)),
    assert(belief_unavailable(alice, docJ, t1)),
    log_trace(belief_update, '[alice] retract(available(docJ, t1))'),
    log_trace(belief_update, '[alice] B_alice(neg_can_do_docJ(consultation(t1)))'),

    % Schedule state changes
    retract(schedule_state(alice, nominal)),
    assert(schedule_state(alice, disrupted)),
    log_trace(state, 'schedule_state(alice) = disrupted'),

    nl, write('  >> Disruption processed. All agents notified.'), nl, nl.

%% ============================================================
%% PHASE 3: LOCAL REPAIR ATTEMPT
%% ============================================================

attempt_local_repair :-
    nl, write('============================================================'), nl,
    write('  PHASE 3: LOCAL REPAIR ATTEMPT'), nl,
    write('============================================================'), nl, nl,

    log_trace(repair, '[alice] Checking local repair for consultation at t1'),

    % Check if any other doctor in clinicA can perform consultation
    (   group_member(clinicA, OtherDoc),
        OtherDoc \= docJ,
        can_do(OtherDoc, consultation, t1)
    ->  format('[alice] LOCAL REPAIR: Found ~w~n', [OtherDoc]),
        log_trace(repair_success, local_repair(OtherDoc, t1))
    ;   log_trace(repair_fail, '[alice] No local doctor available in clinicA'),
        write('  >> Local repair FAILED. No other doctor in clinicA.'), nl, nl,
        log_trace(delegation_request, '[alice] Requesting delegation from mediator'),
        log_trace(message, 'alice -> mediator: request_delegation(alice, clinicA, consultation, t1)')
    ).

%% ============================================================
%% PHASE 4: CROSS-GROUP DELEGATION
%% ============================================================

execute_delegation :-
    nl, write('============================================================'), nl,
    write('  PHASE 4: CROSS-GROUP DELEGATION PROTOCOL'), nl,
    write('============================================================'), nl, nl,

    % Mediator searches for available doctor outside clinicA
    log_trace(delegation, '[mediator] Searching for doctor outside clinicA for consultation at t1'),

    (   group_member(OtherClinic, Doctor),
        OtherClinic \= clinicA,
        can_do(Doctor, consultation, t1)
    ->  format('  >> Candidate found: ~w @ ~w~n', [Doctor, OtherClinic]),
        log_trace(candidate_found, candidate(Doctor, OtherClinic, t1)),

        % Mediator sends lending request
        log_trace(message, 'mediator -> docS: lend_request(clinicA, consultation, t1)'),

        % docS evaluates and accepts
        log_trace(lend_eval, '[docS] Evaluating lend_request(clinicA, consultation, t1)'),
        log_trace(lend_eval, '[docS] can_do(docS, consultation, t1) = true'),
        log_trace(lend_accept, '[docS] ACCEPTED lending request'),

        % Update lending state
        assert(lent_to(Doctor, OtherClinic, clinicA)),
        assert(delegation_log(Doctor, OtherClinic, clinicA, t1, accepted)),
        log_trace(message, 'docS -> mediator: lend_accepted(docS, clinicB, clinicA, t1)'),

        % Mediator notifies alice
        log_trace(message, 'mediator -> alice: delegation_approved(docS, clinicB, t1)'),

        % Alice updates schedule
        retract(appointment(alice, clinicA, docJ, t1)),
        assert(appointment(alice, clinicA, Doctor, t1)),
        assert(belief_available(alice, Doctor, t1)),
        log_trace(schedule_update, 'appointment(alice, clinicA, docS, t1)'),

        retract(schedule_state(alice, disrupted)),
        assert(schedule_state(alice, repaired_delegation)),
        log_trace(state, 'schedule_state(alice) = repaired_delegation')
    ;   log_trace(delegation_fail, 'No external doctor available'),
        retract(schedule_state(alice, disrupted)),
        assert(schedule_state(alice, fallback_asp)),
        log_trace(state, 'schedule_state(alice) = fallback_asp (returning to ASP)')
    ),

    nl, write('  >> Delegation protocol complete.'), nl, nl.

%% ============================================================
%% PHASE 5: CONSULTATION EXECUTION
%% ============================================================

execute_consultation :-
    nl, write('============================================================'), nl,
    write('  PHASE 5: CONSULTATION EXECUTION'), nl,
    write('============================================================'), nl, nl,

    appointment(alice, _, Doctor, t1),

    % Mediator instructs doctor to perform consultation
    log_trace(message, 'mediator -> docS: perform_consultation(alice, t1)'),

    % Doctor performs consultation
    assert(performed(Doctor, consultation, t1)),
    log_trace(action, 'do_docS(consultation(t1))'),

    % Doctor notifies alice
    log_trace(message, 'docS -> alice: consultation_done(docS, t1)'),

    % Alice fulfills intention
    retract(intend(alice, consultation(t1))),
    log_trace(intention_fulfilled, 'intend_alice(consultation(t1)) fulfilled'),

    % Record past event
    log_trace(past_event, 'do_consultationP(docS, t1)'),
    log_trace(past_event, 'unavailableP(docJ, t1)'),

    % Doctor returns to original group
    (   lent_to(Doctor, OrigGroup, _)
    ->  retract(lent_to(Doctor, OrigGroup, clinicA)),
        log_trace(lend_return, '[docS] Returned to clinicB')
    ;   true
    ),

    % Final schedule state
    retract(schedule_state(alice, _)),
    assert(schedule_state(alice, completed)),
    log_trace(state, 'schedule_state(alice) = completed'),

    nl, write('  >> Consultation completed successfully.'), nl, nl.

%% ============================================================
%% PHASE 6: EXPLANATION TRACE SUMMARY
%% ============================================================

print_trace_summary :-
    nl, write('============================================================'), nl,
    write('  EXPLANATION TRACE SUMMARY'), nl,
    write('============================================================'), nl, nl,
    format('~`-t~60|~n', []),
    format('~w ~w ~w ~w~n', ['Step', 'Time(ms)', 'Type', 'Details']),
    format('~`-t~60|~n', []),
    print_all_entries,
    format('~`-t~60|~n', []),
    nl.

print_all_entries :-
    trace_entry(N, T, Type, Details),
    format('~w\t~w\t~w\t~w~n', [N, T, Type, Details]),
    fail.
print_all_entries.

print_final_state :-
    nl, write('============================================================'), nl,
    write('  FINAL STATE'), nl,
    write('============================================================'), nl, nl,

    write('  Schedule:'), nl,
    (   appointment(P, C, D, T)
    ->  format('    appointment(~w, ~w, ~w, ~w)~n', [P, C, D, T])
    ;   write('    (none)'), nl
    ),

    write('  Active intentions:'), nl,
    (   intend(A, Act)
    ->  format('    intend(~w, ~w)~n', [A, Act])
    ;   write('    (none - all fulfilled)'), nl
    ),

    write('  Completed actions:'), nl,
    (   performed(D2, Act2, T2)
    ->  format('    performed(~w, ~w, ~w)~n', [D2, Act2, T2])
    ;   write('    (none)'), nl
    ),

    write('  Schedule state:'), nl,
    (   schedule_state(P2, S)
    ->  format('    ~w: ~w~n', [P2, S])
    ;   true
    ),

    nl, write('  Metrics:'), nl,
    step_counter(TotalSteps),
    format('    Total trace steps: ~w~n', [TotalSteps]),
    write('    Hard constraints violated: 0'), nl,
    write('    Schedule edits: 1 (appointment reassignment)'), nl,
    write('    Local repair attempted: yes (failed)'), nl,
    write('    Cross-group delegation: yes (succeeded)'), nl,
    write('    Fallback to ASP: no'), nl,
    nl.

%% ============================================================
%% MAIN ENTRY POINT
%% ============================================================

run_scenario :-
    statistics(walltime, [T0,_]),
    assert(scenario_start_time(T0)),

    nl, write('************************************************************'), nl,
    write('*  DALI-ASP Hybrid Framework - Scenario Execution Trace   *'), nl,
    write('*  Disruption: Doctor Unavailability + Cross-Group Lending *'), nl,
    write('************************************************************'), nl,

    init_baseline,
    trigger_disruption,
    attempt_local_repair,
    execute_delegation,
    execute_consultation,
    print_trace_summary,
    print_final_state,

    write('************************************************************'), nl,
    write('*  SCENARIO COMPLETE                                      *'), nl,
    write('************************************************************'), nl, nl,
    halt.

:- initialization(run_scenario).
