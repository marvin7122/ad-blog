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

Each cell of the table holds a `ValueId`. For IRIs and literals stored in the main vocabulary, this is a `VocabIndex` —
an opaque integer that points into the on-disk vocabulary.

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

## 3. Profiler evidence
A flamegraph or perf stat output showing that vocabulary lookup dominates the runtime. Do you have a profile from before your changes that we can reference here?

4. Where the bottleneck is
Derive from the profiler: the vocabulary is stored on disk; every ID-to-string translation requires a disk read 
(or at best an OS page cache hit).
With N result rows and T template positions, the original implementation performs up to N×T vocabulary lookups per
query, with no sharing between rows.


# Analysis of Improvement potential for the original Implementation 


# Improved Implementation (Contribution)
The CONSTRUCT query export pipeline is implemented as four sequential phases, each with a single responsibility. The
diagram below gives an overview. The sections that follow describe each phase in detail.

![Data flow diagram](img/data-flow.svg)

### Phase 1 — Template preprocessing (ConstructTemplatePreprocessor)

Input: raw SPARQL CONSTRUCT template triples + variable-to-column map from the query planner.

Output: PreprocessedConstructTemplate, which has two things:
- preprocessedTriples_ — each triple position is now one of three variants: a PrecomputedConstant (IRI/literal, already converted to its final EvaluatedTerm string), a PrecomputedVariable (column index into the IdTable), or a
PrecomputedBlankNode (prefix + suffix precomputed, row number filled in later).
- uniqueVariableColumns_ — the deduplicated set of IdTable column indices that actually appear in the template. This tells phase 2 exactly which columns it needs to evaluate.

This phase runs once per query, before any result rows are seen.

---
Phase 2 — Variable resolution (ConstructBatchEvaluator / evaluateBatch)

Input: uniqueVariableColumns_ + a batch of rows (a contiguous slice of one IdTable).

Output: BatchEvaluationResult — for each column index in uniqueVariableColumns_, a vector of optional<EvaluatedTerm> (one per row in the batch). nullopt means the variable was unbound for that row.

Internally uses an LRU cache to avoid re-resolving the same ValueId for repeated values within a chunk.

---
Phase 3 — Template instantiation (ConstructTripleInstantiator / instantiateBatch)

Input: preprocessedTriples_ (from phase 1) + BatchEvaluationResult (from phase 2).

Output: vector<EvaluatedTriple>. For each (row, template triple) pair: constants are taken directly from the preprocessed template, variables are looked up in the batch result, blank nodes are computed from the row number. Triples where
any term is unbound are silently dropped.

---
Phase 4 — Formatting (FormattedTripleAdapter / StringTripleAdapter in ConstructTripleGenerator)

Input: EvaluatedTriple (three EvaluatedTerms).

Output: either a formatted std::string (Turtle/N-Triples/CSV/TSV) or a StringTriple (three strings, for QLever JSON).

---
Orchestration

`EvaluatedTripleIterator` is the per-chunk worker. It owns the batch loop: given one `TableWithRange`,
it drives phases 2+3 in batches, yielding `EvaluatedTriples` lazily.

`ConstructTripleGenerator` owns the whole pipeline. It runs phase 1 in its constructor,
then for each chunk creates a `TableWithRangeEvaluator`, wraps it in a format adapter (phase 4), and joins the 
per-chunk ranges into a flat output stream.

# Evaluation
TODO: think of representative queries / real world queries / fitting queries to show how performance improved.

# Discussion and Future Work
TODO:Outlook how we can further improve the performance of exporting results, i.e. turning ids into iris/literals
essentially.

TODO: show profile that shows that the largest part of time is needed for the Vocabulary lookup and say that we should
try to improve there next.


# References
[^1]: W3 Org. "RDF Primer" https://www.w3.org/TR/rdf11-primer/ Accessed 2026-03-16.
[^2]: Wikipedia. "RDF" TODO:wikipedia-link-here Accessed 2026-03-17.
[^3]: W3 Org. "SPARQL 1.1 Query Language" https://www.w3.org/TR/sparql11-query/#introduction Accessed 2026-03-18.
[^4]: "QLever Documentation" https://docs.qlever.dev/ Accessed 2026-03-18.
[^5]: "qlever" https://github.com/ad-freiburg/qlever Accessed 2026-03-18.
