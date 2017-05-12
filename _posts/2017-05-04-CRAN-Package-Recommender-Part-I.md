---
layout: post
title: "2017-05-04-CRAN-Package-Recommender-Part-I"
description: ""
category: Serverless
tags: [R, Association Rules, Link Analysis]
---
<style>
.center {
  text-align: center;
}
</style>

One of the attractions of R is 10,000+ [contrubuted packages](https://cran.r-project.org/web/packages/) that can be easily downloaded from the [Comprehensive R Archive Network (CRAN)](https://cran.r-project.org/). Due to the ever-growing number of packages, however, it is not easy to find interesting packages. [CRAN Task Views](https://cran.r-project.org/web/views/) is a good source but, at the time of wrting, it covers only about 2,700 packages. There are some websites that help search R related information such as [RDocumentation](https://www.rdocumentation.org/), [Rseek](http://rseek.org/) or [rdrr-io](https://rdrr.io/). However they seem to rely on *full-text search* so that extra effort is required to identify packages of interest. In this regard, it can be quite useful if there is a *recommender system* so that a set of packages are recommended by a *package name* or general *keywords*. 

[Collaborative filtering](https://en.wikipedia.org/wiki/Collaborative_filtering) is one of the most popular techniques used by recommender systems. However it is not applicable due to the anonymized structure of [CRAN package download logs](http://cran-logs.rstudio.com/) provided by [RStudio](https://www.rstudio.com/). On the other hand, [association rules](https://en.wikipedia.org/wiki/Association_rule_learning) may be mined so that those rules can be used to recommend a package when a user enters a package name. Also package documents (eg package description) can be searched given keywords (eg by [fuzzy text search](http://stackoverflow.com/questions/30449452/python-fuzzy-text-search)) and top packages that are ranked high according to the transactions data may be shown for recommendation.

This is the second series about *serverless data product development*. In this post, a link analysis algorithm called *Hyperlink-Induced Topic Search (HITS)* is introduced. This algorithm helps assign weights on individual transactions and those weights can be used for weighted association rule mining. In the current context, more relevant packages may be recommended by weighted association rules when a package name is entered. Also *HITS* allows to have weights on individual items (packages) so that they can be used to show recommended packages with certain keywords.

The initial series plan is listed below.

Development

* [Introduction to HITS and weighted association rules mining](/2017/05/CRAN-Package-Recommender-Part-I) - this post
* [Downloading/Processing relevant data](/2017/05/CRAN-Package-Recommender-Part-II)
* Analysing CRAN package download logs
* Identifying package similarity
* _to be updated_

Deployment

* _to be updated_

The following packages are used.


{% highlight r %}
library(reshape2)
library(dplyr)
library(igraph)
library(arules)
library(arulesViz)
{% endhighlight %}

## Hyperlink-Induced Topic Search (HITS)

According to [Wikipedia](https://en.wikipedia.org/wiki/HITS_algorithm),

> Hyperlink-Induced Topic Search (HITS; also known as hubs and authorities) is a link analysis algorithm that rates Web pages, developed by [Jon Kleinberg](https://www.cs.cornell.edu/home/kleinber/auth.pdf). The idea behind Hubs and Authorities stemmed from a particular insight into the creation of web pages when the Internet was originally forming; that is, certain web pages, known as hubs, served as large directories that were not actually authoritative in the information that they held, but were used as compilations of a broad catalog of information that led users direct to other authoritative pages. In other words, a good **hub** represented a page that pointed to many other pages, and a good **authority** represented a page that was linked by many different hubs.

As [Sun and Bai (2008)](http://ieeexplore.ieee.org/document/4384488/) discusses, *HITS* can be applied to analysis of transactions database. The key idea is 

* transaction database can be represented as a [bipartite graph](https://en.wikipedia.org/wiki/Bipartite_graph) and thus
* a link-based ranking model (i.e. *HITS*) can be applied to analysis of transactions.

#### Example

It can be a lot easier to illustrate with an example. Below shows simple transaction data - it can also be found in the *arules* package (`data("SunBai")`).


{% highlight r %}
concat_items <- function(data, idcol = 'id') {
    df <- do.call(rbind, lapply(as.data.frame(t(data)), function(e) {
        splt_fac <- ifelse(names(e) == idcol, 'id', 'items')
        splt <- split(e, splt_fac)
        id <- unname(splt[['id']])
        items <- unname(splt[['items']][splt[['items']] != ''])
        data.frame(items = paste0('{', paste(items, collapse = ","), '}'),
                   id = id, stringsAsFactors = FALSE)
    }))
    rownames(df) <- NULL
    df
}

#data("SunBai")
txt <- 'A,B,C,D,E\nC,F,G,,\nA,B,,,\nA,,,,\nC,F,G,H,\nA,G,H,,'
df <- read.csv(text = txt, header = FALSE, stringsAsFactors = FALSE) %>%
    mutate(id = row_number()*100)

concat_items(df)
{% endhighlight %}



{% highlight text %}
##         items  id
## 1 {A,B,C,D,E} 100
## 2     {C,F,G} 200
## 3       {A,B} 300
## 4         {A} 400
## 5   {C,F,G,H} 500
## 6     {A,G,H} 600
{% endhighlight %}

As can be seen above, transactions 200 and 500 have common items of C, F and G, which implies that a strong cross-selling effect exists among them. Although they should be evaluated high, it may not be captured enough if counting-based measurement is employed rather than link-based measurement. On the other hand, although item A has the highest support, it doesn't appear with the valuable items so that it should be evaluated lower. In this circumstance, transactions analysis can be improved by assigning weights on individual transactions and *HITS* provides an algorithmic way of doing so.

#### Graph Representation

The transactions data can be constructed as a bipartite graph as shown below. Note the graph is a directed graph where edges are directed from transaction to individual items.


{% highlight r %}
df_long <- melt(df, id = "id") %>% filter(value != '') %>% select(id, value)
trans <- as(split(df_long[,'value'], df_long['id']), "transactions")

## plot graph
G <- graph.data.frame(df_long)
V(G)$type <- V(G)$name %in% df_long[, 1]
plot(G, layout = layout.bipartite)
{% endhighlight %}

{:.center}
![](/figs/CRAN-Package-Recommender/part1_1.png)

[Adjacency matrix](https://en.wikipedia.org/wiki/Adjacency_matrix) is a square matrix that is used to represent a finite graph. The adjacency matrix of the graph is shown below. In row 1, columns A, B, C, D and E are 1 as transaction 100 includes these items. Only the upper right-hand side of the matrix can have 0 or 1 as the edges are directed only from transaction to items - transaction to transaction and items to items are not possible.


{% highlight r %}
# from igraph
get.adjacency(G) %>% as.matrix()
{% endhighlight %}



{% highlight text %}
##     100 200 300 400 500 600 A C B F G H D E
## 100   0   0   0   0   0   0 1 1 1 0 0 0 1 1
## 200   0   0   0   0   0   0 0 1 0 1 1 0 0 0
## 300   0   0   0   0   0   0 1 0 1 0 0 0 0 0
## 400   0   0   0   0   0   0 1 0 0 0 0 0 0 0
## 500   0   0   0   0   0   0 0 1 0 1 1 1 0 0
## 600   0   0   0   0   0   0 1 0 0 0 1 1 0 0
## A     0   0   0   0   0   0 0 0 0 0 0 0 0 0
## C     0   0   0   0   0   0 0 0 0 0 0 0 0 0
## B     0   0   0   0   0   0 0 0 0 0 0 0 0 0
## F     0   0   0   0   0   0 0 0 0 0 0 0 0 0
## G     0   0   0   0   0   0 0 0 0 0 0 0 0 0
## H     0   0   0   0   0   0 0 0 0 0 0 0 0 0
## D     0   0   0   0   0   0 0 0 0 0 0 0 0 0
## E     0   0   0   0   0   0 0 0 0 0 0 0 0 0
{% endhighlight %}

#### Implementation

[Practical Graph Mining With R](https://www.csc2.ncsu.edu/faculty/nfsamato/practical-graph-mining-with-R/PracticalGraphMiningWithR.html) covers *HITS* algorithm in a comprehensive as well as practical way. In Ch 5, *authority* and *hub* are defined as following.

* Authority - A vertex is considered an authority if it has many pages that link to it (i.e., it has a high indegree).
* Hub - A vertex is considered a hub if it points to many other vertices (i.e., it has a high outdegree).

For transactions database, individual items are candidates of authority while transactions are hub candidates.

In *HITS*, authority and hub scores for each vertex are updated iteratively as following.

1. Initialize authority ($$a$$) and hub ($$h$$) vector scores
2. Iteratively update scores
    + Let $$A$$ be adjacency matrix 
    + Update $$a = A^T\cdot h$$ and $$h = A\cdot a$$
3. Normalize scores
    + Let $$\lVert x\lVert$$ be Euclidean norm
    + Normalize $$a = a/\lVert a\lVert$$ and $$h = h/\lVert h\lVert$$
4. Run until a convergent criterion is met

Note that the implementation is based on the mathematical definition. Note further that the *igraph* or Python's [NetworkX](http://networkx.readthedocs.io/en/stable/reference/generated/networkx.algorithms.link_analysis.hits_alg.hits.html) packages provide their own implementations but their outputs don't seem to be directly applicable - the *arules* has *hits()* function that returns hub scores of a transactoins object but the values are quite different. `run_hits()` executes *HITS* while `get_hits()` collects relevant scores.


{% highlight r %}
run_hits <- function(A, k = 100, tol = 1e-8, verbose = FALSE){
    # mostly from Ch5 of Practical Graph Mining With R
    # https://www.csc2.ncsu.edu/faculty/nfsamato/practical-graph-mining-with-R/PracticalGraphMiningWithR.html
    
    # Get number of nodes(rows) in adjacency matrix
    nodes <- dim(A)[1]
    # 1. Initialize hub and authority vector scores 
    # Initialize authority and hub vector to 1 for each node
    auth <- c(rep(1, nodes)) 
    hub <- c(rep(1, nodes))
    for (i in 1:k) {
        auth_last <- auth
        # 2. Iteratively update the scores
        # Authority and Hub scores are calculated
        auth <- t(A) %*% hub
        hub <- A %*% auth
        # 3. Normalize the scores
        # Normalize Hub and Authority scores
        auth <- auth/sqrt(sum(auth * auth)) 
        hub <- hub/sqrt(sum(hub * hub))
        err <- sum(abs(auth - auth_last))
        if (verbose) message('msg: iteration ', i, ' error - ', err)
        # 4. Run until a convergent criterion is met
        if (err < nodes * tol) {
            break
        }
    }
    if (err > nodes * tol) {
        warning('power iteration failed to converge in ', (i+1), ' iterations')
    }
    return (list(auth = auth, hub = hub))
}

get_hits <- function(A, itemsets, items, k = 100, tol = 1e-6, verbose = FALSE) {
    hits <- run_hits(A, k, tol, verbose)
    hub <- hits$hub[1:length(itemsets)]
    names(hub) <- itemsets
    auth <- hits$auth[(length(itemsets)+1):length(hits$auth)]
    names(auth) <- items
    list(auth = auth, hub = hub)
}
{% endhighlight %}

In order to obtain *authority* and *hub* scores, adjacency matrix is necessary. The *transactions* class of the *arules* package has the *data* slot and it is the upper right-hand side of adjacency matrix. Although it is possilbe to get complete adjacency matrix from the *igraph* package, due to the structure of the matrix, it can be simply obtained by creating the upper left-hand side and bottom matrices of 0's and binding those to the *data* matrix. `get_adj()` returns the adjacency matrix of a transactions object. Note that sparse matrices are created from the *Matrix* package so as to prevent potential *integer overflow error*.


{% highlight r %}
get_adj <- function(trans) {
    itemM <- trans@data
    item_info <- trans@itemInfo[[1]]
    item_no <- length(item_info)
    itemset_info <- trans@itemsetInfo[[1]]
    itemset_no <- length(itemset_info)
    leftM <- sparseMatrix(i = itemset_no, j = itemset_no, x = 0)
    bottomM <- sparseMatrix(i = item_no, j = (itemset_no + item_no), x = 0)
    rBind(cBind(leftM, t(itemM)), bottomM)
}
{% endhighlight %}

The adjacency matrix of the transaction object can be obtained as following.


{% highlight r %}
A <- get_adj(trans)
dimnames(A) <- list(c(trans@itemsetInfo[[1]], trans@itemInfo[[1]]),
                    c(trans@itemsetInfo[[1]], trans@itemInfo[[1]]))
A
{% endhighlight %}



{% highlight text %}
## 14 x 14 sparse Matrix of class "dgCMatrix"
##                                
## 100 . . . . . . 1 1 1 1 1 . . .
## 200 . . . . . . . . 1 . . 1 1 .
## 300 . . . . . . 1 1 . . . . . .
## 400 . . . . . . 1 . . . . . . .
## 500 . . . . . . . . 1 . . 1 1 1
## 600 . . . . . 0 1 . . . . . 1 1
## A   . . . . . . . . . . . . . .
## B   . . . . . . . . . . . . . .
## C   . . . . . . . . . . . . . .
## D   . . . . . . . . . . . . . .
## E   . . . . . . . . . . . . . .
## F   . . . . . . . . . . . . . .
## G   . . . . . . . . . . . . . .
## H   . . . . . . . . . . . . . 0
{% endhighlight %}

With this matrix, it is possible to obtain authority and hub scores. As mentioned, the *arules* package has `hits()` that returns hub scores of a transaction object. It is shown that the hub scores match reasonably. (It is not necessary to obtain hub scores manually but authority scores. Therefore having a reliable function is necessary.)


{% highlight r %}
hub_a <- hits(trans)

hits <- get_hits(A, trans@itemsetInfo[[1]], trans@itemInfo[[1]])
hub <- hits$hub
auth <- hits$auth

hub_compare <- data.frame(trans = names(hub), items = concat_items(df)$items,
                          hub_a = unname(hub_a), hub = unname(hub))
hub_compare
{% endhighlight %}



{% highlight text %}
##   trans       items     hub_a       hub
## 1   100 {A,B,C,D,E} 0.5176528 0.5176047
## 2   200     {C,F,G} 0.4362571 0.4362876
## 3   300       {A,B} 0.2321374 0.2321036
## 4   400         {A} 0.1476262 0.1476079
## 5   500   {C,F,G,H} 0.5440458 0.5440841
## 6   600     {A,G,H} 0.4123691 0.4123721
{% endhighlight %}

The authority scores of C and G are higher than that of A although the support of A is higher. The scores can also be useful for the recommender system.


{% highlight r %}
auth
{% endhighlight %}



{% highlight text %}
##         A         B         C         D         E         F         G 
## 0.4396828 0.2516892 0.5028921 0.1737681 0.1737681 0.3291240 0.4675632 
##         H 
## 0.3210956
{% endhighlight %}

## Weighted Association Rules

In order to compare association rules with/without weights, the hub scores are added to *transactionInfo*.


{% highlight r %}
transactionInfo(trans)[['weight']] <- hub_a
info <- concat_items(df) %>% cbind(weight = transactionInfo(trans)$weight)
info
{% endhighlight %}



{% highlight text %}
##         items  id    weight
## 1 {A,B,C,D,E} 100 0.5176528
## 2     {C,F,G} 200 0.4362571
## 3       {A,B} 300 0.2321374
## 4         {A} 400 0.1476262
## 5   {C,F,G,H} 500 0.5440458
## 6     {A,G,H} 600 0.4123691
{% endhighlight %}

The weighted support of an item is defined as the sum of weights where the item appears divided by the sum of all weights. For example, the weighted support of A is 0.5719366, which can be obtained by

* `sum(info$weight[grepl('A', info$items)])/sum(info$weight)`.

The weighted supports of items C and G are higher than that of A although their counting-based measurements are lower. With this link-based measurement, the resulting association rules may be more useful for the recommender system.


{% highlight r %}
## support
supp_n <- itemFrequency(trans, weighted = FALSE)
supp_w <- itemFrequency(trans, weighted = TRUE)
supp_compare <- data.frame(supp_n = supp_n, supp_w = supp_w)
supp_compare
{% endhighlight %}



{% highlight text %}
##      supp_n    supp_w
## A 0.6666667 0.5719366
## B 0.3333333 0.3274066
## C 0.5000000 0.6541039
## D 0.1666667 0.2260405
## E 0.1666667 0.2260405
## F 0.3333333 0.4280634
## G 0.5000000 0.6081302
## H 0.3333333 0.4176323
{% endhighlight %}


{% highlight r %}
par(mfrow = c(1,2))
itemFrequencyPlot(trans, main = "Unweighted frequency")
itemFrequencyPlot(trans, weighted = TRUE, main = "Weighted frequency")
{% endhighlight %}

{:.center}
![](/figs/CRAN-Package-Recommender/part1_2.png)

As expected, items C, F and G and their combinations are given more importance.


{% highlight r %}
## frequent itemsets
itemsets_n <- eclat(trans, parameter = list(support = 0.3))
{% endhighlight %}



{% highlight text %}
## Eclat
## 
## parameter specification:
##  tidLists support minlen maxlen            target   ext
##     FALSE     0.3      1     10 frequent itemsets FALSE
## 
## algorithmic control:
##  sparse sort verbose
##       7   -2    TRUE
## 
## Absolute minimum support count: 1 
## 
## create itemset ... 
## set transactions ...[8 item(s), 6 transaction(s)] done [0.00s].
## sorting and recoding items ... [6 item(s)] done [0.00s].
## creating bit matrix ... [6 row(s), 6 column(s)] done [0.00s].
## writing  ... [12 set(s)] done [0.00s].
## Creating S4 object  ... done [0.00s].
{% endhighlight %}



{% highlight r %}
itemsets_w <- weclat(trans, parameter = list(support = 0.3))
{% endhighlight %}



{% highlight text %}
## 
## parameter specification:
##  support minlen maxlen target ext
##      0.3      1     10   <NA>  NA
## 
## algorithmic control:
##  sort verbose
##    NA    TRUE
{% endhighlight %}



{% highlight r %}
# apriori
# itemsets_a <- apriori(trans, parameter = list(target = 'frequent', support = 0.3))
# inspect(sort(itemsets_a))

cbind(inspect(sort(itemsets_n)), inspect(sort(itemsets_w)))
{% endhighlight %}


{% highlight text %}
##        items   support   items   support
## [1]      {A} 0.6666667     {C} 0.6541039
## [2]      {C} 0.5000000     {G} 0.6081302
## [3]      {G} 0.5000000     {A} 0.5719366
## [4]    {G,H} 0.3333333     {F} 0.4280634
## [5]  {C,F,G} 0.3333333   {F,G} 0.4280634
## [6]    {C,F} 0.3333333 {C,F,G} 0.4280634
## [7]    {F,G} 0.3333333   {C,F} 0.4280634
## [8]    {A,B} 0.3333333   {C,G} 0.4280634
## [9]    {C,G} 0.3333333     {H} 0.4176323
## [10]     {B} 0.3333333   {G,H} 0.4176323
## [11]     {F} 0.3333333     {B} 0.3274066
## [12]     {H} 0.3333333   {A,B} 0.3274066
{% endhighlight %}

The resulting association rules are shown below.


{% highlight r %}
## rule induction
rules_n <- ruleInduction(itemsets_n, confidence = 0.8)
rules_w <- ruleInduction(itemsets_w, confidence = 0.8)

# apriori
# rules_a <- ruleInduction(itemsets_a, trans, confidence = 0.8)
# inspect(sort(rules_a))
shorten <- function(df) {
    names(df) <- substr(names(df), 1, 3)
    df
}

rules_compare <- cbind(shorten(inspect(sort(rules_n))), shorten(inspect(sort(rules_w))))
rules_compare[, !grepl('Var', names(rules_compare))]
{% endhighlight %}

{% highlight text %}
##       lhs rhs       sup con lif lhs.1 rhs.1     sup.1 con.1    lif.1
## [1]   {H} {G} 0.3333333   1 2.0   {F}   {G} 0.4280634     1 1.644385
## [2] {F,G} {C} 0.3333333   1 2.0 {F,G}   {C} 0.4280634     1 1.528809
## [3] {C,G} {F} 0.3333333   1 3.0 {C,G}   {F} 0.4280634     1 2.336103
## [4] {C,F} {G} 0.3333333   1 2.0 {C,F}   {G} 0.4280634     1 1.644385
## [5]   {F} {C} 0.3333333   1 2.0   {F}   {C} 0.4280634     1 1.528809
## [6]   {F} {G} 0.3333333   1 2.0   {H}   {G} 0.4176323     1 1.644385
## [7]   {B} {A} 0.3333333   1 1.5   {B}   {A} 0.3274066     1 1.748445
{% endhighlight %}

In this post, *HITS* algorithm is introduced and its potential application to a recommender system. In the following posts, CRAN package download logs will be analysed.

<script src='http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML' type="text/javascript"></script>