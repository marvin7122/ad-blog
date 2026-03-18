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
TODO: show that the construct export in comparison to the non-construct export is very slow.

TODO: "we want to make it faster"

# Original Implementation 

TODO: In what kind of worklfow is the construct query export even embedded?


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
