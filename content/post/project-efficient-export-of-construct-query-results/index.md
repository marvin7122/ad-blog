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
The Resource Description Framework (RDF) is a graph based data model where triples of the form \\((s, p, o)\\) denote
directed labeled edges \\(s \overset{p}{\rightarrow} o\\) in a graph. RDF is a framework for expressing information about
*resources*. Resources can be anything, including documents, people, physical objects, and abstract concepts [^1].

TODO: explain what an RDF graph is, using an example and images.

TODO: Explain what RDF triples are in detail, using examples.

TODO: explain that RDF graphs can be represented in different formats. Note that the different formats do not change the
meaning of the triples, just how they are written.

## SPARQL 
TODO: what is it in one sentence

TODO: Explain a very simple example (SELECT) query, also use image

## CONSTRUCT queries 
TODO: what are CONSTRUCT queries?

TODO: what are CONSTRUCT queries used for / useful for?

TODO: example construct query?

## QLever 
TODO: what is qlever in one sentence

TODO: how does the engine work big picture 


TODO: how do the engine work big picture 

# Problem Statement
TODO: show that the construct export in comparison to the non-construct export is very slow.

TODO: "we want to make it faster"

# Approach 
TODO: Explain benchmark -> analyze -> hypothesis -> verification cycle.

# Implementation 
TODO: show profiles of example queries and identify bottlenecks there.

TODO: Analyze the code of the previous version of the algorithms and point out where work is duplicated for example.
And how I managed to deduplicate it.

# Evaluation
TODO: think of representative queries / real world queries / fitting queries to show how performance improved.

# Discussion 
TODO:Outlook how we can further improve the performance of exporting results, i.e. turning ids into iris/literals
essentially.

References
[^1]: W3 Org. "RDF Primer" https://www.w3.org/TR/rdf11-primer/ Accessed 2026-03-16.
