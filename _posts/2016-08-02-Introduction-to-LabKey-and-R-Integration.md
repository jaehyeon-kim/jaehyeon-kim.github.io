---
layout: post
title: "2016-08-02-Introduction-to-LabKey-and-R-Integration"
description: ""
category: R
tags: [LabKey, R]
---

**How** and **What** to deliver are two main themes of my journey to look for an effective way of developing data products. For the former, decent web technologies encompassing HTML, CSS and Javascript are important. However, as I'm not interested in a CRUD-only application, how well to integrate R with an application can be more important. [Shiny](https://www.rstudio.com/products/shiny/) may be a good choice but it wouldn't be the case for the open source edition. Even the enterprise edition or [shinyapps](https://www.shinyapps.io/) might not be suitable as the per-server-based cost model of the former could be too restrictive in AWS environment and I'm not sure how to handle processes that are not related to R in the latter. If Shiny is considered as inappropriate, another R specific option would be [OpenCPU](https://www.opencpu.org/). In spite of interesting examples in the project website, I'm not sure if it catches up recent development trends well especially in reactivity. Then the remaining option is getting involved in typical web development where the **How** part can take much more time and effort than the **What** part. In some cases, this would be a good way to go but, if development projects don't involve a team of web developers, it could be near *mission impossible* in practice.

## What is LabKey server?

On the journey, I happen to encounter an oasis, which is [LabKey Server](https://www.labkey.org/). It is introduced in [Wikipedia](https://en.wikipedia.org/wiki/LabKey_Server) as

> LabKey Server is free, open source software available for scientists to integrate, analyze, and share biomedical research data. The platform provides a secure data repository that allows web-based querying, reporting, and collaborating across a range of data sources. Specific scientific applications and workflows can be added on top of the basic platform and leverage a data processing pipeline.

Although it is mainly targeting biomedical research, I consider it can be applied to other fields without much headache. Below lists some of its key features.

LabKey server supports/includes

* popular [RDBMS (MS SQL, MySQL, PostgreSQL, Oracle) and SAS Data](https://www.labkey.org/home/Documentation/wiki-page.view?name=externalSchemas) as well as Excel, text and [AWS S3](https://www.labkey.org/home/Documentation/wiki-page.view?name=cloudStorage)
* built-in [web parts](https://www.labkey.org/home/Documentation/wiki-page.view?name=buildApps) for UI development
    + data grid and charts can be useful for quick analysis - see [this example](https://labkey.org/home/Documentation/wiki-page.view?name=quickTutorial)
* [scripting engines](https://www.labkey.org/home/Documentation/wiki-page.view?name=configureScripting) including R, Java, Perl as well as SQL queries
    + R via scripting engine or through [RServe](https://www.labkey.org/home/Documentation/wiki-page.view?name=LabKeyRserve)
    + R also has a client package called [Rlabkey](https://cran.rstudio.com/web/packages/Rlabkey/)
    + Python has its own [API](https://www.labkey.org/home/Documentation/wiki-page.view?name=python)
* tight integration with [R outputs (charts ...) as reports](https://www.labkey.org/home/Documentation/wiki-page.view?name=rViews) and even [R Markdown documents](https://www.labkey.org/home/Documentation/wiki-page.view?name=knitr)
* custom web page/application development via [JavaScript API](https://www.labkey.org/home/Documentation/wiki-page.view?name=javascriptAPIs)
    + Note it may incur additional on-off [investment in Ext.js](https://www.labkey.org/home/Documentation/wiki-page.view?name=extDevelopment) to fully utilize the API
* [pipeline server](https://www.labkey.org/home/Documentation/wiki-page.view?name=jms_rps) that can handle heavy/long computing/processing 
* [modules](https://www.labkey.org/home/Documentation/wiki-page.view?name=simpleModules) to package certain functionality such as Workflow or analysis
* good set of [authentication options](https://www.labkey.org/home/Documentation/wiki-page.view?name=authenticationModule)
* useful extra features
    + Message Board
    + Wiki
    + Issue Tracking

Thanks to these features, I consider LabKey server can be used as an **internal collaboration tool** as well as a **framework to deliver products** for external clients, focusing more on the **What** part. In the rest of this post, some basic features of LabKey server is introduced by creating a project and generating a report that consists of a data grid, built-in chart and **R report**.

## Quick example

The latest stable version of LabKey server is 16.2. I installed it on my Windows labtop after downloading the Windows Graphical Installer (*LabKey16.2-45209.14-community-Setup.exe*) from the [product page](http://www.labkey.com/products-services/labkey-server/download-community-edition/). While installing, it sets up SMTP connection and the following components are also added to `C:\Program Files (x86)\LabKey Server`: Java Runtime Environment 1.8.0_92, Apache Tomcat 7.0.69 and PostgreSQL 9.5. Note that installation may fail due to port confliction if you've got Tomcat or PostgreSQL installed already. In this case, it'd be necessary to uninstall existing versions or use the manual installation option.

After installation, the server can be accessed via `http://localhost:8080` - 8080 is the default port of Tomcat server. And it is required to set up a user. Then it is ready to play with.

### Project setup

I set up a *Collaboration* project named **LabkeyIntro** through the following steps.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/01_create_project.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/02_users_permissions.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/03_project_settings.png)

The start page shows *Wiki* and *Messages* web parts in the main panel and a *Pages* web part is shown in the right side bar. Also it is possible to add another web part by seleting and clicking a button.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/04_initial_ui.png)

### Add a list

I removed the existing web parts and added a *Lists* web part in the side bar. By clicking the **MANAGE LISTS** link, it is possible to add a new list. Note that lists are the simplest data structure, which are tabular and have primary keys but don't require participant ids or time/visit information. Check [this](https://www.labkey.org/home/Documentation/wiki-page.view?name=labkeyDataStructures) to see other data structures.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/05_add_list_01.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/06_add_list_02.png)

I imported a simulated customer data of [R for Marketing Research and Analytics](http://r-marketing.r-forge.r-project.org/index.html) and it can be downloaded from [here](http://r-marketing.r-forge.r-project.org/data/).

The imported data is shown in a grid view by clicking the name of the list. By default the following features are provided in a grid view and they are quite useful to investigate/manage data as well as a customized view can be shown as a report.

* sort/filter in _Customize Grid_
* insert or delete a row
* export to Excel, text or script
* print and paging
* add or import fields in _Design_

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/19_grid_view.png)

### Built-in chart

Added to the above features, it provides 3 built-in chart types: Box plot, Scatter plot and Time series plot. I made a scatter plot of *age* versus *credit score*, grouping by a boolean variable of *email* status.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/08_built_chart_01.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/09_built_chart_02.png)

### R report

What's more interesting and useful is its integration with R. While a more sophistigated report can be generated by R markdown, I just added a scatter plot matrices as a R report in this trial. By default, R script engine is not enabled so that it is necessary to turn it on as following.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/17_r_setup_01.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/18_r_setup_02.png)

Note that I only changed the program path and pandoc/rmarkdown is not set up. For further details, see this [article](https://www.labkey.org/home/Documentation/wiki-page.view?name=configureScripting).

Also note that, a package is loaded from where R is installed (eg `C:\Program Files\R\R-3.3.1\library`) so that, if a package is not installed by *administrator*, it is not loaded. For example, I needed the car package but, as it is installed in my user account's site directory (ie `C:\Users\jaehyeon\Documents\R\win-library\3.3`), it was not loaded. In order to resolve this, I opened the R terminal (*R.exe*) as administrator and installed the package as following.

* `install.packages("car", lib="C:\\Program Files\\R\\R-3.3.1\\library", dependencies = TRUE)`

Once it is ready, it is relatively straightforward to add a R output as a report - see the screen shots below.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/10_r_report_01.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/11_r_report_02.png)

Note that a graphics device (`png()`) is explicitly set up.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/12_r_report_03.png)

### Organize project page

Now there are three sections to deliver - data, built-in chart and R report. In order to organize them, I created 3 tabs: *Example Data*, *Built-in Chart* and *R Intro* as shown below.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/13_tabs.png)

A *List - Single* web part is added to Example Data while *Report* web parts are included in the remaining two tabs.

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/14_data_grid.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/15_built_in_chart.png)

![center](/figs/2016-08-02-Introduction-to-LabKey-and-R-Integration/16_r_chart.png)

This is all I've done within several hours. Although only a few basic features are implemented, I consider it provides good amount of information for internal collaboration. 

It's too early but would you consider it's alright to resort to LabKey server as an effective tool for the **How** part? Please inform your ideas.




