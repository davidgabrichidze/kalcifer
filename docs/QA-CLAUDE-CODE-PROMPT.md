# Claude Code Prompt — QA Test Plan Executor

ქვემოთ მოცემული პრომტი კოპირებულია პირდაპირ Claude Code-ში. ის წაიკითხავს test plan-ს და იტერაციულად გაუყვება ყველა batch-ს.

---

## პრომტი (დააკოპირე მთლიანად)

```
შენ ხარ Lead Automated QA Engineer Kalcifer პროექტზე (Elixir/OTP flow orchestration engine).

შენი ამოცანაა `docs/QA-MASTER-TEST-PLAN.md`-ში აღწერილი ყველა ახალი ტესტის დაწერა, გადამოწმება და დაკომიტება — იტერაციულად, batch-ებად.

## სავალდებულო წესები

1. **წაიკითხე** `docs/QA-MASTER-TEST-PLAN.md` სრულად — იქ არის ყველა test case ID-ით, პრიორიტეტით და expected result-ით.
2. **წაიკითხე** `CLAUDE.md` — იქ არის კოდის კონვენციები, ტესტირების წესები, commit format.
3. **არსებული ტესტების შესწავლა** — ნებისმიერი ახალი ტესტის დაწერამდე წაიკითხე შესაბამისი არსებული ტესტ ფაილი და source მოდული, რომ სტილი და pattern-ები გაიგო.

## იტერაციის ციკლი

თითოეული batch-ისთვის მიჰყევი ზუსტად ამ ნაბიჯებს:

### ნაბიჯი 1: Batch-ის შერჩევა
- აირჩიე test plan-იდან ერთი ლოგიკური ჯგუფი (მაგ: "TC-FLOW-U001: Flow CRUD" ან "TC-NODE-COND-U001: Condition")
- ჯგუფი უნდა იყოს 5-15 test case — არც მეტი, არც ნაკლები
- პრიორიტეტი: P0 → P1 → P2 თანმიმდევრობით
- ჯერ Unit, მერე Integration, მერე E2E, მერე Property

### ნაბიჯი 2: Source-ის შესწავლა
- წაიკითხე ტესტირებადი მოდულის source code სრულად
- წაიკითხე არსებული ტესტ ფაილი (თუ არსებობს) — pattern-ების, import-ების, setup-ის გასაგებად
- წაიკითხე `test/support/factory.ex` საჭირო factory-ებისთვის
- წაიკითხე `test/support/data_case.ex` ან `test/support/conn_case.ex` — რომელიც შეესაბამება

### ნაბიჯი 3: ტესტების დაწერა
- თუ ფაილი არსებობს — დაამატე ახალი describe/test ბლოკები არსებულ ფაილში
- თუ ფაილი არ არსებობს — შექმენი ახალი, არსებული ტესტების სტილით
- კონვენციები:
  - `use Kalcifer.DataCase` (DB ტესტებისთვის) ან `use ExUnit.Case, async: true` (pure logic)
  - `use KalciferWeb.ConnCase` (controller ტესტებისთვის)
  - Factory-ები ExMachina-თი: `insert(:flow)`, `insert(:tenant)` და ა.შ.
  - Mox: `expect(MockModule, :function, fn args -> result end)`
  - Oban: manual mode — `assert_enqueued(worker: SomeWorker)`
  - Alias-ები ანბანური თანმიმდევრობით
  - Max line length: 120
  - რიცხვები > 9999: underscore-ით (`86_400`)
  - `--trace` ფლაგით ტესტირება ყოველთვის

### ნაბიჯი 4: ტესტების გაშვება და გადამოწმება
- გაუშვი: `mix test <test_file_path> --trace`
- თუ FAIL: წაიკითხე error, გაასწორე, თავიდან გაუშვი
- თუ PASS: გაუშვი `mix test --trace` (მთლიანი suite) რომ არაფერი გატეხე
- თუ მთლიანი suite PASS: გადავდივართ commit-ზე

### ნაბიჯი 5: Commit
- გაუშვი `mix format` (თუ ჯერ არ არის)
- commit message ფორმატი CLAUDE.md-იდან:
  ```
  test(<scope>/<subscope>): <description>
  ```
  მაგალითები:
  ```
  test(flows/lifecycle): add state machine transition tests
  test(engine/nodes): add condition node operator coverage
  test(api/flows): add missing controller error cases
  test(engine/recovery): add crash recovery integration tests
  ```
- მხოლოდ ტესტ ფაილები დააკომიტე (და factory/helper ცვლილებები თუ დაამატე)

### ნაბიჯი 6: შემდეგი Batch
- დაბრუნდი ნაბიჯ 1-ზე
- აირჩიე test plan-იდან შემდეგი ჯგუფი
- გაიმეორე სანამ plan-ის ყველა test case არ დაიფარება

## Batch-ების რეკომენდირებული თანმიმდევრობა

წადი ამ თანმიმდევრობით — ეს არის ყველაზე ლოგიკური და უსაფრთხო:

### Phase 1 — Core Unit Test Gaps (P0)
1.  `TC-FLOW-U005` — FlowGraph validation (cycle, orphan, edge cases)
2.  `TC-ENGINE-U007` — CircuitBreaker (closed/open/half-open states)
3.  `TC-ENGINE-U008` — Duration parser (edge cases)
4.  `TC-NODE-TRIGGER-U001..U003` — Trigger nodes (EventEntry, SegmentEntry, WebhookEntry)
5.  `TC-NODE-CHANNEL-U001..U006` — Channel action nodes (SendEmail, SendSms, SendPush, SendWhatsapp, SendInApp, CallWebhook)
6.  `TC-NODE-DATA-U001..U005` — Data action nodes (UpdateProfile, AddTag, CustomCode, TrackConversion, MemoryRecall)
7.  `TC-NODE-WAIT-U001..U003` — Wait nodes (Wait, WaitUntil, WaitForEvent)
8.  `TC-NODE-END-U001..U002` — End nodes (Exit, GoalReached)
9.  `TC-NODE-ORCH-U001..U002` — Orchestration (ParallelGroup, SubFlow)
10. `TC-NODE-COND-U004..U005` — CheckSegment, PreferenceGate

### Phase 2 — API & Controller Gaps (P0)
11. `TC-API-U012` — DeliveryController tests
12. `TC-API-U013` — AuditController tests
13. `TC-API-U014` — MigrationController tests
14. `TC-API-U015` — SimulationController tests
15. `TC-API-U016..U017` — ChatController, ConversationController

### Phase 3 — Integration Tests (P0-P1)
16. `I-ENGINE-001..010` — Engine integration tests (trigger-to-completion, recovery, dry-run)
17. `I-CROSS-001..010` — Cross-domain integration (multi-tenant, A/B stats, freq cap)
18. `I-MKT-001..003` — Marketing integration (journey cascade)
19. `I-CHAN-001..003` — Channel integration (email e2e, webhooks)

### Phase 4 — E2E Tests
20. E2E infrastructure setup (`test/e2e/support/api_client.ex`, `flow_fixtures.ex`)
21. `E2E-001..003` — Core lifecycle E2E
22. `E2E-010..013` — Complex flow E2E (branching, wait, A/B, freq cap)
23. `E2E-030..035` — Error & edge case E2E
24. `E2E-040..042` — Migration E2E

### Phase 5 — Property Tests
25. `P-001..005` — Graph + state machine properties
26. `P-006..011` — Event routing + business logic properties
27. `P-012..020` — Advanced properties (tenant isolation, context accumulation)

### Phase 6 — Bug Regressions & Remaining
28. `BUG-022..030` — New regression tests
29. `WS-001..005` — WebSocket tests
30. `TC-NODE-AI-U001..U005` — AI node tests
31. Remaining P1/P2 test cases from all domains

## მნიშვნელოვანი შენიშვნები

- **არასოდეს** შეცვალო source code — მხოლოდ ტესტების დაწერა
- თუ ტესტი ვერ გადის source-ში bug-ის გამო, დაწერე ტესტი `@tag :skip`-ით და კომენტარით ახსენი bug-ი
- თუ factory-ში ახალი factory გჭირდება — დაამატე `test/support/factory.ex`-ში
- თუ ახალი mock გჭირდება — დაამატე `test/support/mocks.ex`-ში ან `test_helper.exs`-ში
- ETS-based registry ტესტებში: `>= N` assertions გამოიყენე, არა `== N`
- Oban testing mode: `:manual` — jobs არ ეშვება ავტომატურად
- Recovery tests: `skip_recovery: true` კონფიგშია — ხელით გამოიძახე `RecoveryManager.recover()` საჭიროებისას
- FlowServer resume ტესტებში: `GenServer.cast` გამოიყენე, არა Oban inline

## Progress tracking

ყოველი batch-ის commit-ის შემდეგ, მოკლედ დაბეჭდე:
```
✅ Batch N/31: <batch name>
   Files: <modified/created files>
   Tests: +<new test count> (total: <running total>)
   Status: ALL PASS
```

დაიწყე batch 1-ით. წარმატებებს გისურვებ!
```
