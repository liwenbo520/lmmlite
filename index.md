---
layout: page
title: R/lmmlite
description: R package with light implementation of linear mixed models for QTL mapping
---

R/lmmlite is a light R package for fitting linear mixed models for
genome-wide association studies (GWAS) and QTL mapping.

I'm following the code in [pylmm](https://github.com/nickFurlotte/pylmm),
and really I'm developing this package mostly so that I can better understand pylmm.

The code is on [GitHub](https://github.com/kbroman/lmmlite).

[Vignette](assets/compare2pylmm.html) with comparisons to
[pylmm](https://github.com/nickFurlotte/pylmm) and
[regress](https://cran.r-project.org/web/packages/regress/).

---

### Installation

You can install R/lmmlite from
[GitHub](https://github.com/kbroman/lmmlite).

You first need to install the
[devtools](https://github.com/hadley/devtools) package.

    install.packages("devtools")

Then use `devtools::install_github()` to install R/lmmlite.

    library(devtools)
    install_github("kbroman/lmmlite")

---

### License

[R/lmmlite](https://github.com/kbroman/lmmlite) is released under the
[GNU Affero GPL](https://www.gnu.org/licenses/why-affero-gpl.html),
because that's the license for
[pylmm](https://github.com/nickFurlotte/pylmm).