# ADR 4 - Use sentence case

Status: Accepted  
Date: 2026-10-02

## Context

We've noticed that in various parts of our platform (UI, documentation,
code, ...) we are making an inconsistent use of "Sentence case" vs "Title
Case".

This [UI stackexchange answer](https://ux.stackexchange.com/a/143500)
summarizes it with the result:

- most guidelines recommend sentence case (Google, Microsoft)
- Apple seems to be the outlier with a title case recommendation and when I
  researched it today their general recommendation says to use whatever style
  consistently.

In addition, even where used title case is not applied correctly in many cases
as it is a convoluted approach with many many special cases, that is hard to
follow, especially on a multi-lingual team.

## Decision

Generally use "sentence case" in UI elements and technical writing.

## Consequences

This is something that is hard to automate via pre-commit hooks or similar and
we will need to train everyone on this. Using AI tools did help  adapt the UI
pretty consistently, so if someone wants to bring a project up to the new
standard.
