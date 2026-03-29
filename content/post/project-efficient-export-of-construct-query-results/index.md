---
title: "Project Efficient Export of Construct Query Results"
date: 2026-03-16T10:11:36+01:00
author: "Marvin Stoetzel"
authorAvatar: "img/ada.jpg"
tags: []
categories: []
image: "img/writing.jpg"
---
The SPARQL CONSTRUCT query form allows clients to extract and transform RDF data into a new graph.
In QLever, the original CONSTRUCT export pipeline was up to 2x slower than an equivalent SELECT export on the same data.
This post describes the analysis of the original implementation, the design and implementation of an improved pipeline,
an empirical evaluation of the speedup achieved, 
and a profiling-based analysis of the remaining overhead that motivates concrete directions for future work.

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

- [Discussion](#discussion)

# Introduction
In the following we will introduce the concepts which are necessary for understanding the context of the improvements
to the CONSTRUCT export pipeline.

## The RDF data model
The RDF data model is based on the idea of making statements about resources (in particular web resources) 
in expressions of the form *subject-predicate-object*, known as *triples*.
The *subject* denotes the resource, the *predicate* denotes traits or aspects of the resource, 
and expresses a relationship between the *subject* and the *object*.[^2]

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
*Listing 1*

RDF statements represent a graph in the following way: 
Each RDF triple statement is represented by: 
(1) a node for the subject, 
(2) a directed edge from subject to object, representing a predicate, and 
(3) a node for the object.

## SPARQL 
SPARQL is an RDF query language, that is, a query language for retrieving and manipulating data stored in RDF format.

Most forms of SPARQL query contain a set of triple patterns called a *basic graph pattern*. 
Triple patterns are like RDF triples except that each of the subject, predicate and object may be a variable 
(a variable is a string that starts with a `?`). 
A basic graph patterm *matches* a subgraph of the RDF data, 
when RDF terms from that subgraph may be substituted for the variables and the result is RDF graph equivalent to the subgraph. [^3]
The most common query form for SPARQL queries is `SELECT`: 
It returnes the results of the query as a table of variable bindings. 
After the `SELECT` keyword, 
one specifies which variable bindings should appear in the result table for the query.
See the following example SPARQL SELECT query which queries for the following:
find everyone (`?person`) who is interested in something (`?thing`) and who created that thing (`?creator`).

```sparql
SELECT ?person ?thing ?creator WHERE {
?person <is interested in> ?thing .
?thing <was created by> ?creator .
}
```

Against our example data (Listing 1), this query returns:

| ?person | ?thing | ?creator |
---------|--------|----------|
| Bob | the Mona Lisa | Leonardo da Vinci |
| Alice | the Mona Lisa | Leonardo da Vinci |

The engine computing the result of the SPARQL query against our knowledge base from above finds all substitutions for
the variables that make every triple pattern of the WHERE clause hold simultaneously.
Alice's interest in the video does not produce a row because no `<was created by>` triple exists for
the video; only combinations, where *all* triple patterns of the WHERE clause match, appear in the result.

## CONSTRUCT queries 
A CONSTRUCT query is a SPARQL query form that produces a new RDF graph rather than a table of variable bindings.
The CONSTRUCT clause specifies a *graph template*, 
which is a set of triple patterns that may contain variables and constants 
(TODO: at this point, the reader does not know what a constant is). 
For each result row (called a query  solution in the SPARQL standard) produced by the WHERE clause, 
the engine substitutes the bound variable values into the graph template and adds the resulting triples to the output graph.
The final output of the CONSTRUCT query is the union of all such triples across all result rows.
If any instantiation produces a triple containing an unbound variable: 
that is, a variable for which the current result row provides no value, that triple is omitted from the output.
Triples in the template that contain no variables at all (called ground triples) appear in the output graph unchanged,
regardless of the result rows.

Consider the following CONSTRUCT query applied to our knowledge base (Listing 1):
```sparql
CONSTRUCT {
?person <has-interest> ?thing .
}
WHERE {
?person <is interested in> ?thing .
}
```

This query produces the following RDF graph as result:
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
"QLever is a graph database implementing the RDF and SPARQL standards.
QLever can efficiently load and query very large datasets, 
even with hundreds of billions of triples, 
on a single commodity PC or server."[^4]
It is a open source project  written in the programming language C++ developed 
by the Chair of Algorithms and  Data Structures at the University of Freiburg [^5]

### Index construction phase 
1. what is a database index?

TODO: how does the engine work big picture 

# Problem Statement
To understand whether the old implementation of the CONSTRUCT query export had a meaningful performance problem, 
we compare the time QLever takes to export a CONSTRUCT query against an equivalent SELECT query on the same data. 
Both queries run the same WHERE clause and therefore do the same query evaluation work. 
The only difference between them is the export step. 
Any gap in export time between the two is attributable to the CONSTRUCT export pipeline itself.

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

**Observation**: The CONSTRUCT export is consistently slower than the equivalent SELECT export acrross all formats and
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

### index building 
TODO:
how an index is built, here we can also explain what the index is, what the vocabulary is etc.

### query resolution

Figure X (TODO) shows how a CONSTRUCT query is processed end-to-end in QLever.

When a client sends an HTTP request containing a SPARQL CONSTRUCT query, the QLever engine processes it in three steps
before the export begins.

1) First, the query string is parsed into a `ParsedQuery`, which is a structured internal representation of the query
(TODO: explain what "structured internal representation" means.) 
2) Second, a `QueryPlanner` derives a `QueryExecutionTree` from the `ParsedQuery`, which is the physical execution plan
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

The core of the CONSTRUCT export is a single function: `constructQueryResultToTriples`. \
Its structure is a straightforward nested loop: \
for each row in the result table 
(the table which is the result from computing the WHERE clause of the CONSTRUCT query) 
iterate over the triple patterns in the CONSTRUCT template and evaluate each triple. \
Evaluating a triple means resolving each of its three positions (subject, predicate, object) to a concrete string. \
If all three resolve successfully, the triple is emitted.

Let's make this concrete via an example, suppose the query is:
```sparql
CONSTRUCT { ?person <has-interest> ?thing }
WHERE     { ?person <is interested in> ?thing }
```

Let us walk through the execution of this CONSTRUCT query on the example knowledge base from earlier (Listing 1). \
The QLever engine executes the WHERE clause and produces the following `IdTable` as result:

| row | `?person` (col 0) | `?thing` (col 1) |
|-----|-------------------|------------------|
| 0   | `VocabId(42)`     | `VocabId(17)`    |
| 1   | `VocabId(99)`     | `VocabId(17)`    |

Each cell of the table holds a `ValueId`. \
For IRIs and literals stored in the main vocabulary, this is a `VocabIndex`, 
(which is an integer that serves as a pointer into the on-disk vocabulary).

The CONSTRUCT template `{ ?person <has-interest> ?thing }` is represented internally as a list of `GraphTerm` triples. \
Each position in a triple is one of: \
a `Variable`, an `Iri`, a `Literal`, or a `BlankNode`.

How a `GraphTerm` is evaluated depends on its type:
- `Iri` or `Literal`: the string representation is stored directly in the object and is returned immediately,
without any vocabulary lookup.
- `Variable`: the variable's column index is looked up in the `IdTable`, the `ValueId` for the current row is
  read, and then resolved to a string via a vocabulary lookup.
- `BlankNode`: the identifier is constructed from the blank node's label and the current row number, producing a 
unique string such as `_:g42_b0`. No vocabulary lookup is needed (TODO: explain somwhere earlier what a BlankNode is).

**Processing row 0:** \
The template triple `?person <has-interest> ?thing` is evaluated term by term. \
The subject `?person` is a `Variable`,
so the implementation reads column 0 of the current result table row, obtaining `VocabId(42)`, and resolves it via a
vocabulary lookup to `"<Bob>"`. \
The predicate `<has-interest>` is an `Iri`, so its string is returned directly from the object without any vocabulary lookup. \
The object `?thing` is again a `Variable`; column 1 yields `VocabId(17)`,
which resolves to `"<the Mona Lisa>"`.

The function emits a \
`StringTriple("<Bob>", "<has-interest>", "<the Mona Lisa>")`.

**Processing row 1:** \
The same template triple is evaluated again from scratch. \
The subject `?person` resolves via column 0 to `VocabId(99)`, which a vocabulary lookup turns into `"<Alice>"`. \
The predicate `<has-interest>` is returned directly from the `Iri` object as before. \
The object `?thing` again yields `VocabId(17)` from column 1, the same `ValueId` as in row 0,
which is looked up independently, again producing `"<the Mona Lisa>"`.

The function emits a \
`StringTriple("<Alice>", "<has-interest>", "<the Mona Lisa>")`.

**Serialization.** \
Once `constructQueryResultToTriples` has yielded a `StringTriple`, a format-specific serializer
produces a stream of string objects according to the output serialization format specified for the query. \
The output format is determined once per request from the HTTP `Accept` header. \
For Turtle, the triple is written as `subject predicate object .`.\
For TSV and CSV, the three strings are escaped and joined with a tab or comma separator.
For QLever JSON, the triple is encoded as a JSON object. \
The serialized output is streamed directly to the HTTP response.

# Analysis of Improvement potential for the original Implementation 
The walkthrough above reveals three structural inefficiencies in the original implementation.

**1. Constants are re-evaluated on every row.** \
Every triple pattern in the CONSTRUCT template is evaluated from scratch for every result row, including constant
positions, i.e. `Iri` and `Literal` terms whose string representation never changes across rows. Although evaluating
a constant is cheap (it just reads a field already in memory), it is unnecessary work that scales linearly with the
number of result rows. A one-time preprocessing step before the row loop begins could resolve constants once and reuse
the result for all rows.

**2. The same `ValueId` is often resolved multiple times.** \
Result tables frequently contain the same `ValueId` in many rows.
In the original implementation, each occurrence triggers an independent vocabulary lookup.
The walkthrough made this visible: `VocabId(17)` appeared in both row 0 and row 1, but was looked up twice.\
A cache that maps recently seen `ValueId`s to their resolved strings would eliminate redundant lookups for repeated values.

**3. Vocabulary lookups are issued one at a time** \
Resolving a `VocabIndex` requires reading from the on-disk vocabulary, which involves decompression and string
construction (depending on how the vocabulary is actually stored on disk, we do not always need decompression here). \
The original implementation issues these lookups individually: \
one lookup per variable position per row. \
Processing rows in batches would allow the implementation to detect duplicate `ValueId`s within one batch before
issuing any lookups at all. \
This way we could also exploit more sequential memory access patterns in the vocuabulary.

# Improved Implementation (Contribution)
The CONSTRUCT query export pipeline is implemented as four sequential phases, each with a single responsibility. The
diagram below gives an overview. The sections that follow describe each phase in detail.

![Data flow diagram](img/data-flow.svg)

### Phase 1 — Template preprocessing (ConstructTemplatePreprocessor)
**Motivation.** In the original implementation, every term in every template triple (including constants) was evaluated
from scratch for every row of the WHERE-clause result table (`IdTable`). A constant like the `Iri` `<has interest>`
always resolves to the same string, independent of the particular result table row. Converting an `Iri` to its string
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
**Motivation.** Phase 1 removed the cost of re-evaluating constants. What remains is resolving `ValueId`s for variable positions. Remember that resolving those terms requires vocabulary lookups and are expensive since the vocabulary is
stored on disk. Two properties can be exploited to do this efficiently.

First, the `IdTable` is stored in column-major order: each column is a contiguous array in memory. If we fetch all `Id`
values for a variable A before moving to variable B, we follow this layout and get sequential memory access. The
original per-row approach: The original per-row approach, evaluating all three template positions for row 0, then row 1
and so on, would jump across columns on every step (except when there is only one variable present in the CONSTRUCT
template).

Second, the `ValueId` values for a single variable column tend to be drawn from a similar region of the `Vocabulary`.
For example, all values in a predicate column are predicate Iris, which are clustered together on disk. Sorting those
`ValueId`s and resolving them in bulk therefore turns scattered disk reads into sequential ones.

Phase 2 exploits both properties by processing one variable column at a time across a batch of rows, and sorting the
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

# Evaluation of original implementation

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

Measurements taken on `construct-pipeline-refactor` branch at `git commit  0480d95`
(https://github.com/marvin7122/qlever/commit/0480d959a02b04d69b017364423ce1670ca833d4).

The build was configured using the following CMake settings:
```
cmake -B build \
-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_C_COMPILER=gcc \
-DCMAKE_CXX_COMPILER=g++ \
-DCMAKE_LINKER=/usr/bin/lld
```

## Evaluation

First, let us use the same `CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }` query from the Problem Statement so we can
compare the old and new implementation of the construct export directly. 

| Format     | Limit | Old (ms) | New (ms) | Speedup |
|------------|-------|----------|----------|---------|
| TSV        | 10k   | 47       | 30       | 1.57x   |
| TSV        | 10M   | TODO     | TODO     | TODO    |
| CSV        | 10k   | 47       | 26       | 1.81x   |
| CSV        | 10M   | TODO     | TODO     | 2.77x   |
| qleverJson | 10k   | 54       | 30       | 1.80x   | 
| qleverJson | 10M   | TODO     | TODO     | TODO    |
| Turtle     | 10k   | 47       | 25       | 1.88x   |
| Turtle     | 10M   | TODO     | TODO     | TODO    |

TODO: create script for these measurements and put it into the artefacts sub folder.

**Observation.** The new implementation is consistently faster than the original across all formats and row counts.
The speedup grows with the number of result rows (from roughly TODO at 10k rows to TODO at 10M rows) 
indicating that the optimizations scale well with result set size.

# Discussion and Future Work

## Profiling the remaining overhead
The new implementation achieves a TODO speedup over the original for TSV, CSV, and Turtle at 10 million rows.
To understand where the remaining time goes and to motivate concrete directions for future work, we profile the
CONSTRUCT export pipeline and compare it against an equivalent SELECT export.

**Choice of queries.**
We profile `CONSTRUCT {?s ?p ?o} WHERE { ?s ?p ?o } LIMIT 10000000` and its SELECT equivalent
`SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000` side by side. 
Both queries evaluate the same WHERE clause;
any difference in their profiles is  therefore attributable to the CONSTRUCT export pipeline itself. 
he SPO query is the most informative subject for profiling because every result row contains three variable positions, 
each of which must be resolved via a vocabulary lookup. 
It maximises the load on the vocabulary access path and represents the worst case for the pipeline we want to understand. 
We use the 10 million limit, in order to be able to gather more data in the profiling. 
Both queries are exported in TSV format. TSV is supported by both query forms and has minimal per-row serialization overhead. 
Using the same format for both queries also ensures that any difference between the two profiles is attributable to improvements the CONSTRUCT pipeline itself rather than to format differences.

**Tool.** We use `perf record`, a statistical sampling profiler that interrupts the process at a fixed frequency and
records the current call stack at each sample. 
After enough samples, the aggregate reveals which functions account for the largest share of CPU time. 
We visualize the output as a flamegraph: 
each bar represents a function, its width proportional to the fraction of samples in which it appeared on the call stack. 
Wide bars near the top of the call stack are the hotspots (bars not near the top of the call stacks are from functions that delegate to callees).

**Build Configuration.** 
We compile the `qlever-server` binary with `RelWithDebInfo` rather than `Release`. 
Both use the same optimization level (TODO: verify), but `RelWithDebInfo` retains debug symbols, 
which allows `perf` to resolve function addresses to human-readable names and to correctly attribute time to inlined call sites. 
We additionally pass `-fno-omit-frame-pointer`, which restores the frame pointer register. 
This flag restores the frame pointer at negligible runtime cost, giving `perf` reliable call stack reconstruction.

The cmake command used is:
`cmake -B build-profile-20260325 \
-DCMAKE_BUILD_TYPE=RelWithDebInfo \
-DCMAKE_C_COMPILER=gcc \
-DCMAKE_CXX_COMPILER=g++ \
-DCMAKE_LINKER=/usr/bin/lld \
-DCMAKE_CXX_FLAGS="-fno-omit-frame-pointer" \
-DCMAKE_C_FLAGS="-fno-omit-frame-pointer"`

**Cache state.** We run each query under two cache conditions.

In the *warm-cache* run, we execute the query once before before profiling to load the relevant index blocks into the OS
page cache (the kernels in-memory buffer of recently accessed file data) (TODO: what is an index block). This isolates
the CPU-bound cost of the export pipeline: vocabulary lookups that miss the LRU cache are served from RAM rather than
disk, so the flamegraph reflects decompression and string construction work rather than I/O wait.

In the *cold-cache* run, we evict the vocabulary file from the OS page cache immediately before recording using
`vmtouch -e`. vmtouch is a utility that inspects and manipulates the page cache residency of specific files.
The `-e` flag evicts all pages of the given file (the files in that subdirectory) from the page cache,
forcing subsequent reads to go to disk. We verify the eviction worked by running `vmtouch` before and after
(it reports the number of pages currently resident  in the page cache for that file/directory, which should fall to zero after eviction.) 
Every vocabulary lookup that misses the LRU cache in the CONSTRUCT export pipeline now requires a real disk read.
Because `perf record` is an on-CPU profiler, it collects no samples while the process is blocked waiting for disk (the
process is simply not scheduled during that time.) A sparse flamegraph from the cold-cache run would therefore be
informative in the following way: it would indicate that the dominant cost is not CPU work but I/O wait.

**Recording procedure.** For each run we start a fresh server instance to avoid QLever's internal query result cache 
returning a pre-computed answer. We attach `perf record` to the running server process, issue the measured query,
and stop recording once the response is complete. We automate the full recording procedure in a single script that
starts a fresh server instance for each run, handles cache warming or dropping as appropriate, attaches `perf record`,
issues the query, and generates the flamegraph.
(The script is available in the repository at `artefacts/2026-03-25_profiling-construct-export.sh`.)
The exact perf record script used is:
`perf record --call-graph fp --freq=997 -p "$SERVER_PID" -o "$perf_out" &`, where `SERVER_PID` is the process id of the
`qlever-server` binary process that is running and `perf_out` is the file to which the profiling data should be written.
A note on thread monitoring: `perf record` supports a `--per-thread` flag which attaches a separate monitoring context
to each thread that exists at the moment `perf` attaches. We initially used this flag, but it produced nearly-empty
profile data, despite the queries running for up to 45 seconds. The reason is that QLever is an HTTP server that spawns
a new worker thread for each incoming request (TODO: citation / proof/ code file reference?). With `--per-thread`, 
`perf` only monitors threads that that already exist at attach time, threads spawned afterwards are not followed.
Since the query worker thread is created only when the HTTP request for the requested query arrives (which happens
after `perf` has already attached) it was never monitored. Without `--perf-thread`, `perf` attaches to the process assembly
a whole and automatically follows all threads including those spawned after attachment, which is the correct behaviour 
for profiling a server process where query work happens on dynamically created threads.
We give perf one second to attach before issuing the query, then send SIGINT rather than SIGTERM to stop it gracefully
after the query completes, ensuring all buffered samples are flushed to disk before perf exits:

```bash
  perf record --call-graph fp --freq=997 -p "$SERVER_PID" -o "$perf_out" &
  PERF_PID=$!
  sleep 1 # give perf time to attach to all threads
  echo "Recording... sending query."
  curl -sf "http://localhost:$SERVER_PORT/?query=$query&action=sparql_query" >/dev/null
  kill -SIGINT "$PERF_PID"
  wait "$PERF_PID" 2>/dev/null || true

```

The sampling frequency is set to 997 Hz rather than a round number to avoid accidentally synchronising with periodic 
system events that fire at round-number intervals, which would bias the sample distribution.

## Results and Observations
**wall-clock times**.
The construct warm query completed in 6,299 ms and the construct cold query in 6,583 ms,
which is a difference of only 284 ms.
The select warm query completed in 10,851 ms and the select cold query 11,083 ms,
a difference of only 232 ms.
Two things stand out.
First, CONSTRUCT is substantially faster than SELECT at 10 million rows (roughly 6.3 seconds vs 10.9 seconds),
the opposite relationship we observed at 1 million rows in the evaluation of the original implementation section.
Second, the warm/cold difference is less than 5% for both queries
Evicting the entire index directory from OS page cache changes total query time by only a few hundred milliseconds.
This might be evidence that the LRU cache is absorbing a vast majority vocabulary lookups before they reach disk,
even on a cold first run. 

**Flame graph analysis**.
The construct-warm flamegraph shows `FormattedTripleAdapter::get` (the top level entry point of the export pipeline)
accounting for 81% of total CPU time.
Within that, two cost centers stand out.
First, `VocabularyOnDisk::operator[]` accounts for 13.77% of total CPU time,
representing the cost of resolving `ValueId`s to strings via disk reads.
Second, `formatTriple` accounts for 18.09% of total CPU time.
The functions that dominate `formatTriple`s call stack are all string manipulation operations
(`RdfEscaping::escapeForTsv`, `absl::strings_internal::CatPieces`, and `__memmove_avx_unaligned`).
This suggests that the serialization step is allocating and copying intermediate strings unnecessarily:
each term is likely escaped into a freshly allocated string,
and the three terms concatenated into yet another string,
rather than being written directly and incrementally into the output buffer.
Eliminating these allocations is a promising optimization direction.

**Why CONSTRUCT outperformed SELECT at 10M rows.**
To understand the reversal, we first analyze the structure of the result set. 
To understand the structure of the result set, we run two queries against the DBLP index.
The first counts the number of distinct subjects, predicates, and objects within the first 10 million rows of 
Running a subquery to count distinct values within the first 10 million rows of the SPO-query.

```sparql
SELECT (COUNT(DISTINCT ?s) AS ?ds) (COUNT(DISTINCT ?p) AS ?dp) (COUNT(DISTINCT ?o) AS ?do) WHERE {
  SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000
}
```

result table:
| ?ds        | ?dp | ?do |
|------------|-----|-----|
|10,000,000  |3    | 3   |


This reveals 10 million distinct subjects, 3 distinct predicates, and 3 distinct objects.

The second query shows how the 10 million rows are distributed across the 9 possible (predicate, object) combinations.

```sparql
SELECT ?p ?o (COUNT(?s) AS ?count) WHERE {
  SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000
} GROUP BY ?p ?o ORDER BY ?p ?o
```

result table:
| ?p              | ?o  | ?count    |
|-----------------|-----|-----------|
|numberOfCreators |0    | 64,366    |
|numberOfCreators |1    | 1,152,843 |
|numberOfCreators |2    | 441,263   |
|signatureOrdinal |1    | 8,338,784 |
|versionOrdinal   |0    | 920       |
|versionOrdinal   |1    | 1,824     |


The formula for the LRU `ValueId`-Cache size is 
`# of distinct variables in the construct template` x `2048`
entries for the binary that was used to create the measurement. 
Thus, for the profiled query, its size is `6,144`. 

The three distinct predicates and three distinct objects together occupy only six of those 6,144 slots 
and likely remain hits  for the entire query after the first batch. 
The remaining 6,138 slots are available for subject lookups, 
but with 10 million distinct subjects this likely provides a 0% 
hit rate for the subject column (all subject terms are different).

Despite the subject column seeing no cache hits, we warm/cold wall-clock difference remains only 284 ms.
To understand why, we inspect which index permutation QLever chose for this query 
(TODO: define earlier what an index permutation is).
QLever's `application/qlever-results+json` format includes a `runtimeInformation` field containing the query execution
plan. (TODO: define somewhere earlier what a query execution plan is).
We retrieve it with the following command against the server started as
`./qlever-server -i dblp -p 7001 --default-query-timeout 3600s`:

```
curl -X POST "http://localhost:7001/query" \
-H "Content-Type: application/sparql-query" \
-H "Accept: application/qlever-results+json" \
--data-binary "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000" \
> /tmp/temp.txt
```

The relevant part of the response is:
```
"query_execution_tree": {
  "description": "LIMIT 10000000",
  "children": [
    {
      "description": "IndexScan OPS ?s ?p ?o",
      "column_names": ["?o", "?p", "?s"],
      "result_rows": 10000000
    }
  ]
}
```

The description field confirms that the query planner (TODO: explain what a query planner is) chose the OPS permutation
(TODO: explain what an OPS permutation is) (IndexScan OPS ?s ?p ?o) (TODO: explain what an index scan is).
Within each (object, predicate) block, subject `ValueIds` therefore arrive in ascending order.
This may contribute to the small warm/cold difference (for example by enabling more sequential access patterns in the
vocabulary file, but a precise explanation would require a more detailed analysis of the vocabulary file layout and 
the actual disk access pattern, which we leave as future work.

## Future Work.
1. **Real-world CONSTRUCT query evaluation.** \
The profiling results are specific to the SPO query, 
which has an unusual result set structure (10M distinct subjects, 3 distinct predicates, 3 distinct objects).
It is unclear how the LRU cache and sort-before-lookup optimization perform under more realistic CONSTRUCT queries.
An open question is also what "real-world CONSTRUCT queries" look like.

2. **`ValueId`-Cache parametrization.** \
The current cache size formula (`# unique variables x 2048`)
was chosen more or less  arbitrarily without proper analysis. \
A structured investigation of cache parametrization would need to address several open questions. \
2.1) What alternative cache parametrization strategies are possible? \
2.2) Along which dimensions can the cache be optimized (example dimensions could be hit rate, memory footprint, query
latency, ...)? \
2.3) Which of the dimensions from 2.2 matters most in practice? \
2.4) Given the most important dimension, how should the cache be parametrized to optimize for it?
miss rates, eviction counts, and memory footprint per query? Possibly also others?) \
2.5) How do we measure the chosen optimization target? \
2.6) How do we approach all of the above in a structured an methodical way? 
For example by running a representative set  of CONSTRUCT queries across a range of cache sizes and datasets, 
and relating the measurements back to the optimization objective.

3. **Investigate blocking I/O and implement batched disk reads.** \
The warm/cold wall-clock difference of only 284 ms suggests the LRU cache is effective for the SPO query, 
but this may not hold for queries that access a larger number of distinct `ValueIds` 
or on large indices like Wikidata (206 GB vocabulary vs TODO vocabulary size for dblp). \
A structured investigation would involve: \
3.1) Understand the vocabulary file layout and access patterns. Understand how `ValueId`s map to positions in the vocabulary file. \
3.2) Establish how to measure blocking I/O time. \
3.3) Define what "representative" queries and datasets mean in this context. \
3.4) Across those representative queries and datasets, quantify the blocking I/O overhead. \
3.5) If blocking I/O is significant, investigate strategies to mitigate it. \
For example replacing individual `pread` calls (system calls that read from disk) for batch misses with batched 
sequential reads, or prefetching vocabulary entries. Understanding how similar systems approach this is a prerequisite. \
3.6) Implement the most promising mitigation strategy. \
3.7) Measure the impact of the implementation across the same representative queries and datasets, comparing blocking
I/O time, wall-clock time, and cache miss rates before and after.

4. **Eliminate unnecessary work in the export pipeline.** \
As identified in the profiling section, `formatTriple` accounts for 18% of CPU time, with the call stack suggesting 
unnecessary intermediate string allocations during escaping and concatenation. \
4.1) In this specific instance, write escaped terms directly into a pre-allocated output buffer. \
4.2) More broadly, the export pipeline should be reviewed for other instances of avoidable work introduced by suboptimal
implementation choices (unnecessary copying, redundant computation, inefficient data structures).

5. **Correctness and testing of the CONSTRUCT export pipeline**. \
5.1) Establish what correct behavior means for the CONSTRUCT export pipeline specifically according to the 
SPARQL 1.1 and RDF standards. Formulate a set of requirements that capture this "correct" behavior. \
5.2) Develop a comprehensive test suite that verifies the pipeline's output against these requirements across a range 
of query templates, edge cases, and output formats. \
5.3) Use this test suite as a safety net for future optimizations, 
ensuring performance improvements do not introduce correctness regressions.

# References
[^1]: W3 Org. "RDF Primer" https://www.w3.org/TR/rdf11-primer/ Accessed 2026-03-16.
[^2]: Wikipedia. "RDF" TODO:wikipedia-link-here Accessed 2026-03-29.
[^3]: W3 Org. "SPARQL 1.1 Query Language" https://www.w3.org/TR/sparql11-query/#introduction Accessed 2026-03-18.
[^4]: "QLever Documentation" https://docs.qlever.dev/ Accessed 2026-03-18.
[^5]: "qlever" https://github.com/ad-freiburg/qlever Accessed 2026-03-18.
