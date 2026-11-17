# Literature step, 2026-11

Every entry below was seen in search results (URL or DOI as listed). Abstract-level reading only unless noted; read the full text before quoting numbers. Decisions: D1 OLT movements are the only loan record, TyLog an input channel. D2 one identity = asset tag plus place code. D3 a DB rule refuses double loans. D5 office redesigned around jobs. D6 typed /loan commands parsed without an LLM. D7 no graph server.

## 1. Provenance and fact lifecycle

- W3C Provenance WG (2013). PROV-O: The PROV Ontology. W3C Recommendation. https://www.w3.org/TR/prov-o/ — supports: `proposed_by` and derivation on every fact (ADR 0002); provenance in append-only logs without a graph server (D7), since PROV-O is only a vocabulary.
- W3C Provenance WG (2013). PROV-DM: The PROV Data Model. W3C Recommendation. https://www.w3.org/TR/prov-dm/ — supports: modelling Source, Item and Decision as entity, activity, agent; also names PROV-CONSTRAINTS for validation.
- Knublauch, Kontokostas (eds.) (2017). Shapes Constraint Language (SHACL). W3C Recommendation. https://www.w3.org/TR/shacl/ — challenges: D7 and D3 only if one assumes a graph store; the supervisor's validation layer is SHACL, ours is Postgres constraints plus typed commands.
- Miles, Bechhofer (eds.) (2009). SKOS Simple Knowledge Organization System Reference. W3C Recommendation. https://www.w3.org/TR/skos-reference/ — supports: aliases and broader/narrower for entity vocabulary (alias / part of); can be exported without a triple store.
- Vrandecic, Krötzsch (2014). Wikidata: A Free Collaborative Knowledgebase. Communications of the ACM 57(10). https://doi.org/10.1145/2629489 — supports: statement status with references (preferred, normal, deprecated) as a working precedent for our proposed/accepted/rejected/obsolete lifecycle.
- Paulheim (2017). Knowledge Graph Refinement: A Survey of Approaches and Evaluation Methods. Semantic Web 8(3). https://doi.org/10.3233/SW-160218 — supports: gold-set precision/recall as the standard way to evaluate correction and completion; coverage metric.
- Zaveri, Rula, Maurino, Pietrobon, Lehmann, Auer (2016). Quality Assessment for Linked Open Data: A Survey. Semantic Web 7(1). https://doi.org/10.3233/SW-150175 — supports: quality dimensions (accuracy, completeness, provenance) behind coverage and precision metrics.
- Hogan et al. (2021). Knowledge Graphs. ACM Computing Surveys 54(4). https://doi.org/10.1145/3447772 — supports: identity and context as separate concerns in a graph (D2); also shows graph model is independent of a graph server (D7).

## 2. Human-in-the-loop entity linking and mixed-initiative interaction

- Settles (2009). Active Learning Literature Survey. University of Wisconsin-Madison CS Technical Report 1648. https://research.cs.wisc.edu/techreports/2009/TR1648.pdf — supports: uncertainty sampling to choose which mentions to show the user; learning-curve evaluation.
- Meduri, Popa, Sen, Sarwat (2020). A Comprehensive Benchmark Framework for Active Learning Methods in Entity Matching. SIGMOD 2020. https://arxiv.org/abs/2003.13114 — supports: quality versus number of labels as the evaluation curve; accept-rate-over-time is the personal-scale analogue.
- Koepcke, Rahm (2010). Frameworks for Entity Matching: A Comparison. Data & Knowledge Engineering 69(2). https://doi.org/10.1016/j.datak.2009.10.003 — supports: gold-set design and the warning that evaluations are hard to compare; challenges: our 100-200 mention gold set is small.
- Wang, Kraska, Franklin, Feng (2012). CrowdER: Crowdsourcing Entity Resolution. PVLDB 5(11). https://arxiv.org/abs/1208.1927 — supports: machine filters obvious pairs, human verifies the rest; cost counted in human judgements.
- Shen, Wang, Han (2015). Entity Linking with a Knowledge Base: Issues, Techniques, and Solutions. IEEE TKDE 27(2). https://doi.org/10.1109/TKDE.2014.2327028 — supports: deterministic resolver stage after mention extraction; standard linking evaluation (precision/recall).
- Amershi, Cakmak, Knox, Kulesza (2014). Power to the People: The Role of Humans in Interactive Machine Learning. AI Magazine 35(4). https://doi.org/10.1609/aimag.v35i4.2513 — supports: Decision log as the feedback channel; users' decisions are noisy and non-stationary, so accept rate is not pure accuracy.
- Mudgal et al. (2018). Deep Learning for Entity Matching: A Design Space Exploration. SIGMOD 2018. https://doi.org/10.1145/3183713.3196926 — challenges: a learned matcher needs many labels; supports a rule-based resolver with a feedback ledger at small scale.

## 3. Natural language to structured commands with deterministic validation

- Berant, Chou, Frostig, Liang (2013). Semantic Parsing on Freebase from Question-Answer Pairs. EMNLP 2013. https://aclanthology.org/D13-1160/ — supports: semantic parsing as a baseline framing; background for D6.
- Shin et al. (2021). Constrained Language Models Yield Few-Shot Semantic Parsers. EMNLP 2021. https://aclanthology.org/2021.emnlp-main.608 — supports: restrict output to a controlled sublanguage that maps to a formal meaning; closest to a typed /loan grammar (D6).
- Willard, Louf (2023). Efficient Guided Generation for Large Language Models. arXiv:2307.09702 (Outlines). https://arxiv.org/abs/2307.09702 — supports: grammar or regex constrained decoding if an LLM is later used; challenges: D6 only in that an LLM path exists.
- Patil et al. (2025). The Berkeley Function Calling Leaderboard (BFCL): From Tool Use to Agentic Evaluation of Large Language Models. ICML 2025, PMLR 267. https://proceedings.mlr.press/v267/patil25a.html — supports: argument-level correctness is measured by AST match; single-turn calls are good, multi-turn and memory are not, so an LLM is not the safe write path for loans.
- Tam et al. (2024). Let Me Speak Freely? A Study on the Impact of Format Restrictions on Performance of Large Language Models. EMNLP 2024 Industry Track. https://aclanthology.org/2024.emnlp-industry.91 — supports: format restriction can hurt reasoning, so keep the LLM as a free-text mention extractor and validate outside it.
- Schick et al. (2023). Toolformer: Language Models Can Teach Themselves to Use Tools. NeurIPS 2023. https://arxiv.org/abs/2302.04761 — challenges: D6 (shows tool calls by LLM are feasible); supports keeping calls behind a typed registry with checks.

## 4. Lab and equipment inventory, ledgers and record accuracy

- DeHoratius, Raman (2008). Inventory Record Inaccuracy: An Empirical Analysis. Management Science 54(4). https://doi.org/10.1287/mnsc.1070.0789 — supports: counted-share of places and audits as the lever against record error; a reported 65% of records inaccurate at one retailer (secondary report, verify).
- Kang, Gershwin (2005). Information Inaccuracy in Inventory Systems: Stock Loss and Stockout. IIE Transactions 37. https://dspace.mit.edu/handle/1721.1/36193 — supports: unrecorded loss (not logged movements) causes inaccuracy; argues for D1 and one identity (D2). Year differs by source (2003 or 2005).
- Panko (1998, rev. 2008). What We Know About Spreadsheet Errors. Journal of End User Computing 10(2). https://doi.org/10.4018/joeuc.1998040102 — supports: spreadsheet loan lists carry high error rates; baseline for the per-source silo.
- Helland (2015). Immutability Changes Everything. CIDR 2015 (also CACM 59(1), 2016). https://ceres.cs.umd.edu/818/papers/immutability.pdf — supports: append-only log as the truth and derived views on top (D1, append-only movements).
- Overeem, Spoor, Jansen, Brinkkemper (2021). An Empirical Characterization of Event Sourced Systems and Their Schema Evolution: Lessons from Industry. Journal of Systems and Software 178. https://doi.org/10.1016/j.jss.2021.110970 — challenges: append-only ledgers; reports schema evolution, learning curve and projection rebuilds as costs.
- Kotecha et al. (2025). Digital Twins in Engineering and Design Education: A Systematized Review. ASEE Annual Conference. https://peer.asee.org/digital-twins-in-engineering-and-design-education-a-systematized-review — supports: OpenLabTwin framing; the review says larger-scale evaluations are still needed, so a single-lab study is a small addition. (Page returned 403 on 2026-11-17: authors and venue unverified, check before citing.)

## 5. Attention, interruption, triage and PIM

- Whittaker, Sidner (1996). Email Overload: Exploring Personal Information Management of Email. CHI 1996. https://doi.org/10.1145/238386.238530 — supports: inbox as to-do list; triage cost and lost items; ignore rate and decision latency.
- Mark, Gudith, Klocke (2008). The Cost of Interrupted Work: More Speed and Stress. CHI 2008. https://www.ics.uci.edu/~gmark/chi08-mark.pdf — supports: interruptions have a stress cost, justifying attention as the scarce resource and a low taps/seconds-per-job target (D5).
- Iqbal, Horvitz (2010). Notifications and Awareness: A Field Study of Alert Usage and Preferences. CSCW 2010. https://www.erichorvitz.com/shamsi_iqbal-eric_horvitz_cscw_2010.pdf — supports: users value awareness but find alerts distracting; ignoring is informative (ignore rate).
- Pielot, Church, de Oliveira (2014). An In-Situ Study of Mobile Phone Notifications. MobileHCI 2014. https://doi.org/10.1145/2628363.2628364 — supports: notification volume measured in the field; baseline for counting shown versus acted.
- Mehrotra, Hendley, Musolesi (2016). PrefMiner: Mining User's Preferences for Intelligent Mobile Notification Management. UbiComp 2016. https://doi.org/10.1145/2971648.2971747 — supports: learn from dismiss/accept behaviour; reported dismissal prediction precision above 91% with title and location features; precedent for improvement from the Decision log.
- Bergman, Beyth-Marom, Nachmias (2006). The Project Fragmentation Problem in Personal Information Management. CHI 2006. https://doi.org/10.1145/1124772.1124813 — supports: per-format silos fragment one project; the core claim for one Item model across sources.
- Jones (2008). Keeping Found Things Found: The Study and Practice of Personal Information Management. Morgan Kaufmann. https://www.elsevier.com/books/catalog/isbn/9780123708663 — supports: finding, re-finding and keeping as PIM activities; framework for coverage and re-finding.
- Bergman, Whittaker (2016). The Science of Managing Our Digital Stuff. MIT Press. https://academic.oup.com/mit-press-scholarship-online/book/22884 — supports: integrated versus separated personal collections; design for how people actually organize.

## 6. Small-scale evidence: graph, RDF, relational

- Angles, Gutierrez (2008). Survey of Graph Database Models. ACM Computing Surveys 40(1). https://doi.org/10.1145/1322432.1322433 — supports: graph is a data model, not a product; a file index can hold one (D7).
- Sahu, Mhedhbi, Salihoglu, Lin, Özsu (2020). The Ubiquity of Large Graphs and Surprising Challenges of Graph Processing: Extended Survey. The VLDB Journal 29. https://doi.org/10.1007/s00778-019-00548-x — supports: relational databases still play an important role in managing graphs in practice (D7); but the study stresses large graphs, so it is weak evidence for a small single lab.
- Hartig (2017). RDF* and SPARQL*: An Alternative Approach to Annotate Statements in RDF. ISWC 2017 Posters. https://ceur-ws.org/Vol-1963/paper593.pdf — challenges: D7 on one point; plain RDF needs four triples to reify a statement, so per-fact provenance is costly in RDF, easier in property graph or row form.
- Hartig, Thompson (2014). Foundations of an Alternative Approach to Reification in RDF. arXiv:1406.3399. https://arxiv.org/abs/1406.3399 — challenges: RDF for statement-level provenance; supports choosing rows with status columns for fact status.

## Gaps

- Small-scale performance of Postgres versus Neo4j versus an RDF store for a single lab: I found only blog, student and conference-paper benchmarks whose titles or authors I could not confirm, so none are listed. Needs a targeted ACM or IEEE search.
- Lab and makerspace equipment loan systems: no peer-reviewed comparison of loan-tracking systems. A Tufts dissertation on an IoT makerspace equipment system and an MDPI chemical-warehouse paper exist, but I could not confirm author, title or venue details, so they are left out.
- Event sourcing versus CRUD for inventory accuracy: no direct empirical comparison; only Overeem et al. on practice, plus practitioner blogs (excluded).
- Digital twins in laboratory (not classroom) settings: the evidence base is small and recent; only one review is listed.
- Fact status workflow in knowledge-graph curation (extracted, pending, validated, contested, rejected): Wikidata ranks are the only solid precedent found; no peer-reviewed study of a contested status.
- Accept-rate-over-time as a metric for a personal assistant: PrefMiner is the closest; no paper found that reports it for linking.
- Integrated versus siloed PIM with a measured effect size: Bergman et al. 2006 is qualitative; no controlled comparison found.
- Not read in full: all entries were read at abstract or search-snippet level.
