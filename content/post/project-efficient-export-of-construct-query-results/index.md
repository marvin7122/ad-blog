---
title: "Project Efficient Export of Construct Query Results"
date: 2026-03-16T10:11:36+01:00
author: "Marvin Stoetzel"
authorAvatar: "img/ada.jpg"
tags: []
categories: []
image: "img/writing.jpg"
---

Summary goes here

<!--more-->
# Table of Contents
- [Introduction](#introduction)
  - [RDF](#RDF)
  - [SPARQL](#SPARQL)
  - [CONSTRUCT queries](#Construct)
  - [QLever](#QLever)
- [Problem Statement](#problem_statement)
- [Approach](#approach)
- [Previous Work](#Previous_Work)
- [Implementation](#implementation)
- [Evaluation](#evaluation)

TODO: maybe explain somwhere, how the SELECT export works, currently.
- [Discussoin](#discussion)

# Introduction
## RDF
The Resource Description Framework (RDF) is a method to describe and exchange graph data.[^2]

RDF allows us to make statements about resources. The format of these statements is simple.
A statement always has the following structure:\
`<subject> <predicate> <object>`

An RDF statement expresses a relationship between two resources. The subject and the object represent the two resources
being related; the predicate represents the nature of their relationship. The relationship is phrased in a directional
way (from subject to object). RDF statements are also called triple statements, since one statement consists of three
parts: subject, predicate, and object.

Below is an example of multiple RDF triples, which are seperated by a dot (.) and a newline.
```ntriples
<Bob> <is a> <person>.
<Bob> <is a friend of> <Alice>.
<Bob> <is born on> <the 4th of July 1990>. 
<Bob> <is interested in> <the Mona Lisa>.
<the Mona Lisa> <was created by> <Leonardo da Vinci>.
<the video 'La Joconde à Washington'> <is about> <the Mona Lisa>
<Alice> <is interested in> <the Mona Lisa>.
<Alice> <is interested in> <the video 'La Joconde à Washington'>.

```
TODO: add name for this, sample data 1 or sth.

RDF statements represent a graph in the following way: Each RDF triple statement is represented by: (1) a node
for the subject, (2) a directed edge from subject to object, representing a predicate, and (3) a node for the object.

TODO: visualize the dataset from above
Fig. 1 shows a visualization of the graph resulting from the triples above.

## SPARQL 
SPARQL is an RDF query language, that is, a query language for retrieving and manipulating data stored in RDF format.

Most forms of SPARQL query contain a set of triple patterns called a _basic graph pattern_. Triple patterns are like
RDF triples except that each of the subject, predicate and object may be a variable (a variable is a string that starts
with a `?`). A basic graph patterm _matches_ a subgraph of the RDF data when RDF terms from that subgraph may be
substituted for the variables and the result is RDF graph equivalent to the subgraph. [^3]

The most common query form for SPARQL queries is `SELECT`: It returnes the results of the query as a table of variable
bindings. After the `SELECT` keyword, one specifies which variable bindings should appear in the result table for the
query.

See the following example SPARQL SELECT query which queries for the following:
find everyone (`?person`) who is interested in something (`?thing`) and who created that thing (`?creator`).

```sparql
SELECT ?person ?thing ?creator WHERE {
?person <is interested in> ?thing .
?thing <was created by> ?creator .
}
```

Against our example data (sample data 1), this query returns:

| ?person | ?thing | ?creator |
---------|--------|----------|
| Bob | the Mona Lisa | Leonardo da Vinci |
| Alice | the Mona Lisa | Leonardo da Vinci |


TODO: maybe say first what an engine is in this context.

The engine computing the result of the SPARQL query against our knowledge base from above finds all substitutions for
the variables that make every triple pattern of the WHERE clause hold simultaneously.

Alice's interest in the video does not produce a row because no `<was created by>` triple exists for
the video; only combinations, where *all* triple patterns of the WHERE clause match, appear in the result.

## CONSTRUCT queries 
A CONSTRUCT query is a SPARQL query form that produces a new RDF graph rather than a table of variable bindings.
The CONSTRUCT clause specifies a *graph template*, which is a set of triple patterns that may contain variables and
constants (TODO: at this point, the reader does not know what a constant is). For each result row (called a query 
solution in the SPARQL standard) produced by the WHERE clause, the engine substitutes the bound variable values into
the graph template and adds the resulting triples to the output graph.
The final output of the CONSTRUCT query is the union of all such triples across all result rows.

If any instantiation produces a triple containing an unbound variable: that is, a variable for which the current result
row provides no value — that triple is omitted from the output.

Triples in the template that contain no variables at all (called ground triples) appear in the output graph unchanged,
regardless of the result rows.

--
Consider the following CONSTRUCT query applied to our example data:

CONSTRUCT {
?person <has-interest> ?thing .
}
WHERE {
?person <is interested in> ?thing .
}

This produces the following RDF graph:

```ntriples
<Bob> <has-interest> <the Mona Lisa>.
<Alice> <has-interest> <the Mona Lisa>.
<Alice> <has-interest> <the video 'La Joconde à Washington'>.
```

Unlike the SELECT query from the previous section, the result is not a table but a new set of RDF triples that can be
stored, exported, or queried further.

CONSTRUCT queries are particularly useful when the goal is not to inspect data in a table,
but to export or transform it as RDF.
Common use cases include extracting a subgraph from a large knowledge base for use in another system or producing a
self-contained RDF file for exchange or archival.

## QLever 
"QLever is a graph database implementing the RDF and SPARQL standards. QLever can efficiently load and query very large 
datasets, even with hundreds of billions of triples, on a single commodity PC or server."[^4]
It is a open source project written in the programming language C++ developed by the Chair of Algorithms and 
Data Structures at the University of Freiburg [^5]

TODO: how does the engine work big picture 

# Problem Statement
The CONSTRUCT query export takes the result table produced by the WHERE clause and transforms it into an RDF graph by
instantiating the CONSTRUCT template for each result row. The resulting triples are then serialized into the requested
output format and streamed to the client.

To understand whether the old implementation of the CONSTRUCT query export had a meaningful perfomance problem, we
compare the time QLever takes to export a CONSTRUCT query against an equivalent SELECT query on the same data. Both
queries run the same WHERE clause and therefore do the same query evaluation work. The only difference between them is
the export step. Any gap in export time between the two is attributable to the CONSTRUCT export pipeline itself.

## Benchmarking Setup

To measure the cost of the CONSTRUCT export pipeline in isolation, we compare the time QLever takes to answer a
CONSTRUCT query against an equivalent SELECT query on the same data. Both queries evaluate the same WHERE clause. Any
perfomance gap between the two is therefore attributable to the CONSTRUCT pipeline itself.

**Query.** We use the following query, which retrieves every triple in the dataset:
```sparql
SELECT ?s ?p ?o WHERE { ?s ?p ?o }
```

For the CONSTRUCT variant, the template directly mirrors the SELECT projection:
```sparql
CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }
```

We vary the number of result rows using `LIMIT` (10,000 / 100,000 / 1,000,000) in order to see whether a potential
perfomance gap scales with the number of rows.

**Output format.** SELECT queries are most commonly exported in tabular formats such as TSV or CSV (TODO: quote?).
CONSTRUCT queries produce RDF graphs, which are most commonly serialized as Turtle or N-Triples (TODO: quote?).

Not all formats are supported by both query forms.
QLever silently falls back to a default when an unsupported format is requested (`turtle` is the default format for
CONSTRUCT and `sparqlJson` the default format for SELECT query outputs).

A fair comparison therefore requires formats that both  query forms support natively.
The formats common to both are TSV, CSV, qleverJson.

We benchmark `TSV`, `CSV`, and `qleverJson`  for the SELECT vs CONSTRUCT comparison.
Additionally, we report `Turtle` times for CONSTRUCT queries in isolation, since `Turtle` is the most common output
format for RDF graph export (next to `N-Triples`, which is not supported for construct-query exports at the moment.)

**Methodology.** We use QLever's internal query time, which covers the full request handling but excludes network
transfer. We run the query once before measuring to ensure the index is loaded into the OS page cache, then run the same
query five times and report median of the 5  measurements.

**Machine.** All measurements were taken at git `commit af00534d` from the master branch of the qlever repo [^5]) on a
machine with the following specifications:
- CPU: AMD Ryzen 5 4600G
- RAM: 30.7 GiB
- Storage: Lexar NM620 1 TB NVMe SSD
- OS: Fedora 42, Kernel 6.8.13, x86\_64

The binary was compiled in Release mode using GCC with the LLD linker:
`cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_LINKER=/usr/bin/lld ..`

TODO: rerun the benchmark at git commit a5e4bf705f003cb3b0477c068966a633a15fb378 (since I did the refactor afterwards)

## Results

| Output format | LIMIT     | SELECT (ms)    | CONSTRUCT (ms)     | Ratio |
|---------------|-----------|----------------|------------------- |-------|
| TSV           | 10k       | 29             | 46                 | 1.59x |
| TSV           | 100k      | 191            | 363                | 1.90x |
| TSV           | 1M        | 1575           | 3479               | 1.98x |
| CSV           | 10k       | 29             | 47                 | 1.62x |
| CSV           | 100k      | 191            | 362                | 1.90x |
| CSV           | 1M        | 1738           | 3486               | 2.01x |
| qleverJson    | 10k       | 39             | 52                 | 1.33x |
| qleverJson    | 100k      | 272            | 422                | 1.55x |
| qleverJson    | 1M        | 2580           | 4084               | 1.58x |
| Turtle        | 10k       | not supported  | 47                 | None  |
| Turtle        | 100k      | not supported  | 354                | None  |
| Turtle        | 1M        | not supported  | 3401               | None  |

The `SELECT (ms)` and `CONSTRUCT (ms)` columns report the median wall-clock time in milliseconds over the five measured
runs. The `Ratio` column is the CONSTRUCT time divided by the SELECT time.

**Observation**: The CONSTRUCT export is consitently slower than the equivalent SELECT export acrross all formats and
row counts. For TSV and CSV the CONSTRUCT export takes approximately 2x as long at 1 million rows. The ratio grows
slightly with the number of rows (from ~1.6x at 10k rows to ~2x at 1M rows), indicating that the overhead of the
CONSTRUCT export pipeline scales roughly linearly with the number or result rows.

The ratio is lower for `qleverJson` (~1.6x at 1M rows). This is expected: qleverJson is a more verbose format that
requires more seralization  work per row for both query forms, which reduces the relative share of CONSTRUCT-specific
overhead in the total time. (TODO: does that really make sense?)

For the turtle format, no SELECT comparison is possible since QLever does not support Turtle output for SELECT queries.
The absolute CONSTRUCT times for Turtle are comparable to those for TSV and CSV, which makes sense since all three
formats produce one line per output triple (whereas the qleverJson format produces more than that).

In the next section we examine the original implementation of the CONSTRUCT Export pipeline to understand how we can
improve it.

# Original Implementation 
## 1. Where it fits in
Figure X (TODO) shows how a CONSTRUCT query is processed end-to-end in QLever.

When a client sends an HTTP request containing a SPARQL CONSTRUCT query, the QLever engine processes it in three steps
before the export begins.

1) First, the query string is parsed into a `ParsedQuery`, which is a structured internal representation of the query
(TODO: explain what "structured internal representation" means.) 
2) Second, a `QueryPlanner` derives a `QueryExecutionTree` fro the `ParsedQuery`, which is the physical execution plan
for the query.
3) Third, the `QueryExecutionTree` is executed against the index (TODO: explain what an index is first), producing the
 result of the where clause as a `Result` object. The `Result` contains an `IdTable`: a table of rows where each row
represents a query solution and each cell holds a `ValueId`, which is a compact 64-bit integer encoding of an RDF term.
The `Result` also contains a `LocalVocab` object, which is an in-memory vocabulary, which holds RDF terms created during
query execution that are not present in the main on-disk vocabulary (TODO: explain what a vocabulary is.)

This `Result` is the input to the CONSTRUCT export. For each row in the `IdTable`, the export instantiates the CONSTRUCT
 template: it resolves each `ValueId` back into a human-readable RDF term string (by looking the corresponding string
representation up in the `LocalVocab` or the main `vocabulary` on disk), substitutes the resolved strings into the
template positions, and emits the resulting triples into the requested output format, which is then streamed back to the
client in the appropriate serialization format.

## 2. How the original implementation worked

The core of the CONSTRUCT export is a single function: `constructQueryResultToTriples`. Its structure is a
straightforward nested loop: for each row in the result table (the table which is the result from computing the WHERE clause of
the CONSTRUCT query) iterate over the triple patterns in the CONSTRUCT template and evaluate each triple.
Evaluating a triple means resolving each of its three positions (subject, predicate, object) to a concrete string.
If all three resolve successfully, the triple is emitted.

To make this concrete, suppose the query is:

```sparql
CONSTRUCT { ?person <has-interest> ?thing }
WHERE     { ?person <is interested in> ?thing }
```

Let us walk through the execution of this CONSTRUCT query on the example knowledge base (TODO: back reference to the KB
from above). The QLever engine executes the WHERE clause and produces the following `IdTable` as result:

| row | `?person` (col 0) | `?thing` (col 1) |
|-----|-------------------|------------------|
| 0   | `VocabId(42)`     | `VocabId(17)`    |
| 1   | `VocabId(99)`     | `VocabId(17)`    |

Each cell of the table holds a `ValueId`. For IRIs and literals stored in the main vocabulary, this is a `VocabIndex`, 
an integer that serves as a pointer into the on-disk vocabulary.

The CONSTRUCT template `{ ?person <has-interest> ?thing }` is represented internally as a list of `GraphTerm` triples.
Each position in a triple is one of: a `Variable`, an `Iri`, a `Literal`, or a `BlankNode`. How a `GraphTerm` is
evaluated depends on its type:

- **`Iri` or `Literal`**: the string representation is stored directly in the object and is returned immediately,
without any vocabulary lookup.
- **`Variable`**: the variable's column index is looked up in the `IdTable`, the `ValueId` for the current row is
  read, and then resolved to a string via a vocabulary lookup.
- **`BlankNode`**: the identifier is constructed from the blank node's label and the current row number, producing a 
unique string such as `_:g42_b0`. No vocabulary lookup is needed (TODO: explain somwhere earlier what a BlankNode is).

**Processing row 0:**
The template triple `?person <has-interest> ?thing` is evaluated term by term. The subject `?person` is a `Variable`,
so the implementation reads column 0 of the current result table row, obtaining `VocabId(42)`, and resolves it via a
vocabulary lookup to `"<Bob>"`. The predicate `<has-interest>` is an `Iri`, so its string is returned directly from the object —
`"<has-interest>"` — without any lookup. The object `?thing` is again a `Variable`; column 1 yields `VocabId(17)`,
which resolves to `"<the Mona Lisa>"`.

The function emits a `StringTriple("<Bob>", "<has-interest>", "<the Mona Lisa>")`.

**Processing row 1:**
The same template triple is evaluated again from scratch. The subject `?person` resolves via column 0 to `VocabId(99)`,
which a vocabulary lookup turns into `"<Alice>"`. The predicate `<has-interest>` is returned directly as before. The
object `?thing` again yields `VocabId(17)` from column 1 — the same `ValueId` as in row 0 — which is looked up
independently, again producing `"<the Mona Lisa>"`.

The function emits a `StringTriple("<Alice>", "<has-interest>", "<the Mona Lisa>")`.

**Serialization.** Once `constructQueryResultToTriples` has yielded a `StringTriple`, a format-specific serializer
produces a stream of string objects according to the output serialization format specified for the query.
The output format is determined once per request from the HTTP `Accept` header.
For Turtle, the triple is written as `subject predicate object .`.
For TSV and CSV, the three strings are escaped and joined with a tab or comma separator.
For QLever JSON, the triple is encoded as a JSON object. The serialized output is streamed directly to the
HTTP response.

# Analysis of Improvement potential for the original Implementation 
The walkthrough above reveals three structural inefficiencies in the original implementation.

**1. Constants are re-evaluated on every row.**
Every triple pattern in the CONSTRUCT template is evaluated from scratch for every result row, including constant
positions, i.e. `Iri` and `Literal` terms whose string representation never changes accross rows. Although evaluating
a constant is cheap (it just reads a field already in memory), it is unnecessary work that scales linearly with the
number of result rows. A one-time preprocessing step before the row loop begins could resolve constants once and reuse
the result for all rows.

**2. The same `ValueId` is often resolved multiple times.**
Result tables frequently contain the same `ValueId` in many rows. A commmon predicate Iri for example appears in the
same column for every row. In the original implementation, each occurrence triggers an independendant vocabulary lookup.
The walkthrough made this visible: `VocabId(17)` appeared in both row 0 and row 1, but was looked up twice. A cache that
maps recently seen `ValueId`s to their resolved strings would eliminate redundant lookups for repeated values.

**3. Vocabulary lookups are issued one at a time**
Resolving a `VocabIndex` requires reading from the on-disk vocabulary, which involves decompression and string
construction. The original implementation issues these lookups individually: one lookup per variable position per row.
Processing rows in batches would allow the implementation to detect duplicate `ValueId`s within one batch before
issuing any lookups at all. This way we could also exploit more sequential memory access patterns in the vocuabulary.
This amortizes the per-lookup cost accross many rows at once.

# Improved Implementation (Contribution)
The CONSTRUCT query export pipeline is implemented as four sequential phases, each with a single responsibility. The
diagram below gives an overview. The sections that follow describe each phase in detail.

![Data flow diagram](img/data-flow.svg)

### Phase 1 — Template preprocessing (ConstructTemplatePreprocessor)
**Motivation.** In the original implementation, every term in every template triple (including constants) was evaluated
from scratch for every row of the WHERE-clause result table (`IdTable`). A constant like the `Iri` `<has interest>`
always resolves to the same string, independendant of the particular result table row. Converting an `Iri` to its string
representation constructs a new string object every time.

`ConstructTemplatePreprocessor::preprocess` transforms the raw `GraphTerm` triples from the CONSTRUCT clause into a
`PreprocessedConstructTemplate`. Each term position is converted into on of three variants:

- `PrecomputedConstant`: for `Iri` and `Literal` terms: the string is resolved immediately and stored as
`shared_ptr<const EvaluatedTermData>`. Because the object is a shared pointer, the same object is reused for every
result row without per-row allocation or string copying.
- `PrecomputedVariable`: for `Variable` terms: the variable is resolved to its column index in the `IdTable`.
- `PrecomputedBlankNode`: for `BlankNode` terms: the prefix (`_:g` for generated blank nodes, `_:u` for user-defined)
and suffix (_ + label) are precomputed. At row time, only the row number needs to be inserted between them to produce a
valid evaluted BlankNode.

A CONSTRUCT template may contain multiple triple patterns, and the same variable may appear in more than one of them.
In the original implementation, such a variable would be evaluated independently for each triple pattern it appears in
for every result table row. To avoid this overhead, the preprocessing phase creates `uniqueVariableColumns_`: the
deduplicated list of `IdTable` column indices that appear as variables anywhere in the template triples.
We will in Phases 2 and 3 how the improved construct export pipeline make use of `uniqueVariableColumns_`.

Phase 1 runs once per query, before any rows of the result table are processed.

---
### Phase 2 — Variable resolution (ConstructBatchEvaluator / evaluateBatch)
**Motivation.** Phase 1 removed the cost of re-evaluating constants. What remains is resolving `ValueId`s for variable
positions. Remember that resolving those terms requires vocabulary lookups and are expensive since the vocabulary is
stored on disk. Two properties can be exploited to do this efficiently.

First, the `IdTable` is stored in column-major order: each column is a contiguous array in memory. If we fetch all `Id`
values for a variable A before moving to variable B, we follow this layout and get sequential memory access. The
original per-row approach: The original per-row approach, evaluating all three template positions for row 0, then row 1
and so on, would jump across columns on every step (except when there is only one variable present in the CONSTRUCT
template).

Second, the `ValueId` values for a single variable column tend to be drawn from a similar region of the `Vocabulary`.
For example, all values in a predicate column are predicate Iris, which are clustered together on disk. Sorting those
`ValueId`s and resolving them in bulk therefore turns scattered disk reads into sequential ones.

Phase 2 exploits both properties by processing one variable column at a time accross a batch of rows, and sorting the
`ValueId`s within each column before lookup.

`evaluateBatch` receives `uniqueVariableColumns_` from phase 1 and a `BatchEvaluationContext` describing a contiguous
slice of the `IdTable`. For each variable column, `evaluateVariableByColumn` proceeds in two sub-steps.

1. ***Sort and cache check**. The `Id` values for that column across all rows in the batch are collected and sorted. For
   each sorted `ValueId`, the LRU cache is checked first. Cache hits are written directly to the result; misses are
collected into a separate list.
2. **Batch resolution of misses**. The sorted list of cache-miss `ValueId`s  is passed to `idsToStringAndType`, which
   resolves them in bulk. The results are inserted into the cache and scattered back to the per-row positions in the
  output.

The output is a `BatchEvaluationResult`: a map from column index to a per-row vector of `optional<EvaluatedTerm>`. A
`nullopt` entry means the variable was unbound for that row.

The LRU cache is owned by `TableWithRangeEvaluator` and passed into `evaluateBatch`, so it persists across batches
within the same `TableWithRange`, allowing cache hits even when the same `ValueId` recurs across batch boundaries.

---
### Phase 3 — Template instantiation (ConstructTripleInstantiator / instantiateBatch)

**Motivation**. At this point all vocabulary work is done. Phase 3 is a pure assembly step: combine the precomputed
template structure from phase 1 with the resolved variable values from phase 2.

`instantiateBatch` iterates over every (row, template triple) pair.
For each term position, according to the term variant:
- `PrecomputedConstant`: the precomputed `EvaluatedTerm` shared pointer is copied into the output. This is a
reference-count increment, not a string copy.
- `PrecomputedVariable`: the resolved value is looked up in the `BatchEvaluationResult` by column index and row. If the
  value is `nullopt` the entire triple is dropped.
-`PrecomputedBlankNode`: the blank node string is constructed from the precomputed prefix, the current absolute row
index of the current row, and the precomputed suffix.

The output is a `vector<EvaluatedTriple>` for the batch, with unbound triples already filtered out. (TODO: explain
somewhere earlier when a triple is unbound and why that occurs)

---
### Phase 4 — Formatting (FormattedTripleAdapter / StringTripleAdapter in ConstructTripleGenerator)

**Motivation**. Phases 1-3 produce `EvaluaedTriple` objects, which contain the resolved term data without any
output-format-specific serialization applied. Phase 4 now serializes the the `EvaluatedTriple` objects according to the
specified seralization format.

Two adapter classes inside `ConstructTripleGenerator.cpp` wrap a `TableWithRangeEvaluator` and pull `EvaluatedTriple`
objects from it one at a time:
- `FormattedTripleAdapter`: serializes each `EvaluatedTriple` into a `std::string`, applying the escaping and separators
  appropriate for the `MediaType` selected from the HTTP Accept header. It handles the Turtle, N-triples, TSV, and CSV
formats.
- `StringTripleAdapter`: formats each term into a string and returns a `StringTriple` (three separate strings), which is
  what the QLever JSON serialier consumes.
---
### Orchestration

`ConstructTripleGenerator` is the entry point for the whole pipeline. It runs phase 1 in its constructor. For each
`TableWithRange` chunk of the result table, it creates a `TableWithRangeEvaluator` (which drives phases 2 and 3) and
wraps it either in a `FormattedTripleAdapter` or a `StringTripleAdapter` (phase 4), depending on the requested output
format. The per-chunk ranges are joined into a flat lazy output stream and passed directly to the HTTP response writer.

# Evaluation

We evaluate the improved CONSTRUCT export pipeline against the original implementation on the DBLP dataset.
We design targeted experiments that aim to highlight the contribution of each individual optimization, as well as
measuring the overall improvement on a representative baseline query.

## Methodology
We use the same machine and build configuration as in the Problem Statement. For each experiment we run the query once
as warmup to ensure the index (TODO: explain what an index is somewhere) is loaded into the OS page cache (TODO: explain
what the OS page cache is and why we want the index to be loaded into the OS page cache.), then run the query five times
and report the median wall-clock time for the query as reported by the qlever engine without the network transfer
overhead. Each measurement uses a fresh server instance to avoid interference from QLever's internal query cache.
We report times in milliseconds; ratios are new implementation time divided by old implementation time (lower is better).

### Experiment 1: Baseline SPO query
First, let us use the same `CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }` query from the Problem Statement so we can
compare the old and new implementation directly. This allows us to connect back to the original overhead reported there
and see how much of it the new implementation eliminates.

| Format     | Limit | Old (ms) | New (ms) | Speedup |
|------------|-------|----------|----------|---------|
| TSV        | 10k   | 47       | 30       | 1.57x   |
| TSV        | 100k  | 364      | 144      | 2.53x   |
| TSV        | 1M    | 3481     | 1274     | 2.73x   |
| CSV        | 10k   | 47       | 26       | 1.81x   |
| CSV        | 100k  | 367      | 144      | 2.55x   |
| CSV        | 1M    | 3488     | 1259     | 2.77x   |
| qleverJson | 10k   | 54       | 30       | 1.80x   |
| qleverJson | 100k  | 422      | 190      | 2.22x   |
| qleverJson | 1M    | 4069     | 1731     | 2.35x   |
| Turtle     | 10k   | 47       | 25       | 1.88x   |
| Turtle     | 100k  | 358      | 137      | 2.61x   |
| Turtle     | 1M    | 3389     | 1184     | 2.86x   |

**Observation.** The new implementation is consistently faster than the original across all formats and row counts.
The speedup grows with the number of result rows — from roughly 1.6–1.9x at 10k rows to 2.4–2.9x at 1M rows —
indicating that the optimizations scale well with result set size. This is expected: the benefits of constant
preprocessing, column-major batch evaluation, and LRU caching all accumulate as more rows are processed.

The pattern across formats mirrors what we observed in the Problem Statement: qleverJson shows the smallest speedup
(~2.4x at 1M rows) while TSV, CSV, and Turtle show larger gains (~2.7–2.9x). As noted before, the more verbose
qleverJson format requires more serialization work per row for both implementations, which reduces the relative share
of the CONSTRUCT-specific overhead that the new implementation eliminates.

### Experiment 2: Constant preprocessing

**Motivation.** In the original implementation, every term in every template triple is evaluated from scratch for every
result row, including constant positions whose string representation does not change across result table rows.
Phase 1 of the new implementation eliminates this by resolving constants once at preprocessing time and reusing the
result for all rows.

To isolate this effect, we use a CONSTRUCT template that contains only constants:
`CONSTRUCT { <s> <p> <o> } WHERE { ?s ?p ?o }`. Since the template contains no variables, neither implementation
performs any vocabulary lookups during export. Any difference in runtime between the old and new implementation is
therefore entirely attributable to how efficiently the two implementations handle constant template terms.

| Format     | Limit | Old (ms) | New (ms) | Speedup |
|------------|-------|----------|----------|---------|
| TSV        | 10k   | 17       | 13       | 1.31x   |
| TSV        | 100k  | 35       | 32       | 1.09x   |
| TSV        | 1M    | 181      | 181      | 1.00x   |
| CSV        | 10k   | 13       | 17       | 0.76x   |
| CSV        | 100k  | 36       | 32       | 1.12x   |
| CSV        | 1M    | 190      | 193      | 0.98x   |
| qleverJson | 10k   | 20       | 17       | 1.18x   |
| qleverJson | 100k  | 67       | 66       | 1.02x   |
| qleverJson | 1M    | 488      | 487      | 1.00x   |
| Turtle     | 10k   | 13       | 18       | 0.72x   |
| Turtle     | 100k  | 30       | 29       | 1.03x   |
| Turtle     | 1M    | 157      | 160      | 0.98x   |

**Observation.** The new implementation shows no meaningful speedup over the original for a constants-only template.
The ratios range from 0.72x to 1.31x with no consitent trend and converge to 1.00x at 1M rows across the three measured
formats.

This result is expected in retrospect. Each `Iri` or `Literal` in the CONSTRUCT template is part of the parsed query
object, which already holds its string representation in memory. Evaluating it per row is just reading a field, which
is a cheap operation. Phase 1 replaces this with a shared-pointer copy, which is comparably cheap. The per-row
saving is too small to be visible against the cost of query execution and serialization.

TODO: should we also do some more experiments here?

# Discussion and Future Work

## Profiling the remaining overhead
The new implementation achieves a 2.7-2.9x speedup over the original for TSV, CSV, and Turtle at one million rows.
To understand where the remaining time goes and to motivate concrete directions for future work, we profile the
CONSTRUCT export pipeline and compare it against an equivalent SELECT export.

**Choice of queries.** We profile `CONSTRUCT {?s ?p ?o} WHERE { ?s ?p ?o } LIMIT 10000000` and its SELECT equivalent
`SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000` side by side. Both queries evaluate the same WHERE clause; any
difference in their profiles is  therefore attributable to the CONSTRUCT export pipeline itself. The SPO query is the
most informative subject for profiling because every result row contains three variable positions, each of which must be
resolved via a vocabulary lookup. It maximises the load on the vocabulary access path and represents the worst case for
the pipeline we want to understand. We use the 10 million limit, in order to be able to gather more data in the
profiling.

**Tool.** We use `perf record`, a statistical sampling profiler that interrupts the process at a fixed frequency and
records the current call stack at each sample. After enough samples, the aggregate reveals which functions account for
the largest share of CPU time. We visualize the output as a flamegraph: each bar represents a function, its width
proportional to the fraction of samples in which it appeared on the call stack. Wide bars near the top of the call stack
are the hotspots (bars not near the top of the call stacks are from functions that delegate to callees).

**Build Configuration.** We compile the `qlever-server` binary with `RelWithDebInfo` rather than `Release`. Both use the
same optimization level (TODO: verify), but `RelWithDebInfo` retains debug symbols, which allows `perf` to resolve
function addresses to human-readable names and to correctly attribute time to inlined call sites. We additionally pass
`-fno-omit-frame-pointer`, which restores the frame pointer register. This flag restores the frame pointer at negligible
runtime cost, giving `perf` reliable call stack reconstruction.
The cmake command used is:
`cmake -B build-profile-20260325   -DCMAKE_BUILD_TYPE=RelWithDebInfo   -DCMAKE_C_COMPILER=gcc   -DCMAKE_CXX_COMPILER=g++   -DCMAKE_LINKER=/usr/bin/lld   -DCMAKE_CXX_FLAGS="-fno-omit-frame-pointer"   -DCMAKE_C_FLAGS="-fno-omit-frame-pointer"`

**Cache state.** We run each query under two cache conditions.

In the *warm-cache* run, we execute the query once before before profiling to load the relevant index blocks into the OS
page cache (the kernels in-memory buffer of recently accessed file data) (TODO: what is an index block). This isolates
the CPU-bound cost of the export pipeline: vocabulary lookups that miss the LRU cache are served from RAM rather than
disk, so the flamegraph reflects decompression and string construction work rather than I/O wait.

In the *cold-cache* run, we evict the vocabulary file from the OS page cache immediately before recording using
`vmtouch -e`. vmtouch is a utility that inspects and manipulates the page cache residency of specific files.
The `-e` flag evicts all pages of the given file from the page cache, forcing subsequent reads to go to disk.
We verify the eviction worked by running `vmtouch` before and after (it reports the number of pages currently resident 
in the page cache for that file/directory, which should fall to zero after eviction.) 
Every vocabulary lookup that misses the LRU cache in the CONSTRUCT export pipeline now requires a real disk read.
Because `perf record` is an on-CPU profiler, it collects no samples while the process is blocked waiting for disk (the
process is simply not scheduled during that time.) A sparse flamegraph from the cold-cache run would therefore be
informative in its own right: it would indicate that the dominant cost is not CPU work but I/O wait, and that `perf
record` is the wrong tool for that scenario. In that case we follow up with `bftrace` using an off-CPU flamegraph, which
captures the call stack at the moment the process is put to sleep and measures how long it stays blocked, attributing
disk-wait time to the code that triggered it.

**Recording procedure.** For each run we start a fresh server instance to avoid QLever's internal query result cache 
returning a pre-computed answer. We attach `perf record` to the running server process, issue the measured query,
and stop recording once the response is complete. We automate the full recording procedure in a single script that
starts a fresh server instance for each run, handles cache warming or dropping as appropriate, attaches `perf record`,
issues the query, and generates the flamegraph.
The script is available in the repository at `artefacts/2026-03-25_profiling-construct-export.sh`.
The sampling frequency is set to 997 Hz rather than a round number to avoid accidentally synchronising with periodic 
system events that fire at round-number intervals, which would bias the sample distribution.
The flamegraph is generated with Brendan Gregg's FlameGraph scripts.




TODO:Outlook how we can further improve the performance of exporting results, i.e. turning ids into Iris/Literals
essentially.

TODO: show profile that shows that the largest part of time is needed for the Vocabulary lookup and say that we should
try to improve there next.

TODO: how large of space does the Idcache take up? Measure rss resident set size.

TODO: how large is the cache? Measure rss resident set size.


# References
[^1]: W3 Org. "RDF Primer" https://www.w3.org/TR/rdf11-primer/ Accessed 2026-03-16.
[^2]: Wikipedia. "RDF" TODO:wikipedia-link-here Accessed 2026-03-17.
[^3]: W3 Org. "SPARQL 1.1 Query Language" https://www.w3.org/TR/sparql11-query/#introduction Accessed 2026-03-18.
[^4]: "QLever Documentation" https://docs.qlever.dev/ Accessed 2026-03-18.
[^5]: "qlever" https://github.com/ad-freiburg/qlever Accessed 2026-03-18.
