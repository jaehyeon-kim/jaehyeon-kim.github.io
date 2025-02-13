---
title: Realtime Dashboard with Streamlit and Next.js - Part 2 Streamlit Dashboard
date: 2025-02-25
draft: true
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
categories:
  - Data Product
tags: 
  - Python
  - Streamlit
  - Apache ECharts
  - WebSocket
authors:
  - JaehyeonKim
images: []
description:
---

In this post, we develop a real-time monitoring dashboard using [Streamlit](https://streamlit.io/), an open-source Python framework that allows data scientists and AI/ML engineers to create interactive data apps. The app connects to the WebSocket server we developed in [Part 1](/blog/2025-02-18-realtime-dashboard-1) and continuously fetches data to visualize key metrics such as **order counts**, **sales data**, and **revenue by traffic source and country**. With interactive bar charts and dynamic metrics, users can monitor sales trends and other important business KPIs in real-time.

<!--more-->

* [Part 1 Data Producer](/blog/2025-02-18-realtime-dashboard-1)
* [Part 2 Streamlit Dashboard](#) (this post)
* Part 3 Next.js Dashboard

## Deploy Data Producer

The data generator and WebSocket server can be deployed using Docker Compose with the command `docker-compose -f producer/docker-compose.yml up -d`. Once started, the server can be checked with a [WebSocket client](https://github.com/lewoudar/ws/) using the command `ws listen ws://localhost:8000/ws`, and its logs can be monitored by running `docker logs -f producer`. The source code for this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/product-demos).

![](backend.gif#center)

## Streamlit Frontend

This Streamlit dashboard is designed to process and display real-time *theLook eCommerce data* using *pandas* for data manipulation, Streamlit's built-in *metric* component for KPIs, and *Apache ECharts* for visualizations.

### Components

The dashboard components and data processing logic are managed by functions in `utils.py`. Below are the details of those functions.

1. Loading Records:
   - The `load_records()` function accepts a list of records, converts them into a **pandas DataFrame**, and ensures that the necessary columns are present.
   - It then processes data by converting the **age** column to integers and the **cost** and **sale_price** columns to floating-point values, rounding the sale price to one decimal place.
   - Key metrics like the **number of orders**, **number of order items**, and **total sales** are calculated from the DataFrame and returned for display.

2. Generating Metrics:
   - The `create_metric_items()` function creates a list of dictionaries containing metrics and their respective changes (`delta`), comparing the current and previous values of **orders**, **order items**, and **total sales**.
   - The `generate_metrics()` function takes the calculated metrics and displays them in Streamlit’s **metric components** within the `placeholder` container. It uses a column layout to show the metrics side-by-side.

3. Creating Chart Options:
   - The `create_options_items()` function generates configuration data for bar charts that display **revenue by country** and **revenue by traffic source**. 
   - It groups the data by **country** and **traffic source**, sums the **sale_price** for each, and sorts it in descending order. 
   - **ECharts options** are defined for each chart with custom colors, titles, and axis settings. The charts are configured to show **tooltips** when hovering over the bars.

4. Displaying Charts:
   - The `generate_charts()` function takes the **ECharts options** and renders each chart within a container using the `st_echarts` component of the [streamlit-echarts](https://pypi.org/project/streamlit-echarts/) package.
   - Each chart is placed in its own column, with dynamic layout adjustments based on the number of charts being displayed. The charts are rendered with a fixed height of **500px**.

```python
## producer/streamlit/utils.py
from uuid import uuid4

import pandas as pd
import streamlit as st
from streamlit.delta_generator import DeltaGenerator
from streamlit_echarts import st_echarts


def load_records(records: list):
    df = pd.DataFrame(records)
    assert set(
        [
            "order_id",
            "item_id",
            "country",
            "traffic_source",
            "age",
            "cost",
            "sale_price",
        ]
    ).issubset(df.columns)
    df["age"] = df["age"].astype(int)
    df["cost"] = df["cost"].astype(float)
    df["sale_price"] = df["sale_price"].astype(float).round(1)
    metric_values = {
        "num_orders": df["order_id"].nunique(),
        "num_order_items": df["item_id"].nunique(),
        "total_sales": round(df["sale_price"].sum()),
    }
    return metric_values, df


def create_metric_items(metric_values, prev_values):
    return [
        {
            "label": "Number of Orders",
            "value": metric_values["num_orders"],
            "delta": (metric_values["num_orders"] - prev_values["num_orders"]),
        },
        {
            "label": "Number of Order Items",
            "value": metric_values["num_order_items"],
            "delta": (
                metric_values["num_order_items"] - prev_values["num_order_items"]
            ),
        },
        {
            "label": "Total Sales",
            "value": f"$ {metric_values['total_sales']}",
            "delta": (metric_values["total_sales"] - prev_values["total_sales"]),
        },
    ]


def generate_metrics(placeholder: DeltaGenerator, metric_items: list = None):
    if metric_items is None:
        metric_items = [
            {"label": "Number of Orders", "value": 0, "delta": 0},
            {"label": "Number of Order Items", "value": 0, "delta": 0},
            {"label": "Total Sales", "value": 0, "delta": 0},
        ]
    with placeholder.container():
        for i, col in enumerate(st.columns(len(metric_items))):
            metric = metric_items[i]
            col.metric(
                label=metric["label"], value=metric["value"], delta=metric["delta"]
            )


def create_options_items(df: pd.DataFrame):
    colors = [
        "#00008b",
        "#b22234",
        "#00247d",
        "#f00",
        "#ffde00",
        "#002a8f",
        "#000",
        "#003580",
        "#ed2939",
        "#003897",
        "#f93",
        "#bc002d",
        "#024fa2",
        "#000",
        "#00247d",
        "#ef2b2d",
        "#dc143c",
        "#d52b1e",
        "#e30a17",
    ]
    chart_cols = [
        {"x": "country", "y": "sale_price"},
        {"x": "traffic_source", "y": "sale_price"},
    ]
    option_items = []
    for col in chart_cols:
        data = (
            df[[col["x"], col["y"]]]
            .groupby(col["x"])
            .sum()
            .reset_index()
            .sort_values(by=col["y"], ascending=False)
        )
        options = {
            "title": {"text": f"Revenue by {col['x'].replace('_', ' ').title()}"},
            "xAxis": {
                "type": "category",
                "data": data[col["x"]].to_list(),
                "axisLabel": {"show": True, "rotate": 75},
            },
            "yAxis": {"type": "value"},
            "series": [
                {
                    "data": [
                        {"value": d, "itemStyle": {"color": colors[i]}}
                        for i, d in enumerate(data[col["y"]].to_list())
                    ],
                    "type": "bar",
                }
            ],
            "tooltip": {"trigger": "axis", "axisPointer": {"type": "shadow"}},
        }
        option_items.append(options)
    return option_items


def generate_charts(placeholder: DeltaGenerator, option_items: list):
    with placeholder.container():
        for i, col in enumerate(st.columns(len(option_items))):
            options = option_items[i]
            with col:
                st_echarts(options=options, height="500px", key=str(uuid4()))
```

### Application

The dashboard connects to the **WebSocket server** to fetch and display real-time *theLook eCommerce* data. Here's a detailed breakdown of its functionality:

1. WebSocket Connection:
   - The `generate()` function is an **asynchronous** task that establishes a connection to a WebSocket server (`ws://localhost:8000/ws`) using an asynchronous HTTP client by the [aiohttp](https://pypi.org/project/aiohttp/) package. It listens for incoming messages from the server, which contain the eCommerce data.
   - As each message is received, the function loads the data using the `load_records()` function, which processes the data into **pandas DataFrame** format and computes key metrics.

2. Generating and Displaying Metrics:
   - The `create_metric_items()` function calculates and prepares key metrics (such as **number of orders**, **order items**, and **total sales**) along with the delta (changes) from the previous values.
   - The `generate_metrics()` function updates the Streamlit dashboard by displaying these metrics in the `metric_placeholder`.

3. Creating and Displaying Charts:
   - The `create_options_items()` function processes the data and generates configuration options for bar charts, displaying **revenue by country** and **traffic source**.
   - The `generate_charts()` function renders the charts in the `chart_placeholder` container, using **ECharts** for interactive data visualizations.

4. Real-time Updates:
   - The loop continuously listens for new data from the WebSocket server. As data is received, it updates both the metrics and charts in real-time.

5. User Interface:
   - The app sets a wide layout with the title **"theLook eCommerce Dashboard"**. 
   - A checkbox (`Connect to WS Server`) lets the user choose whether to connect to the WebSocket server. When checked, the dashboard fetches data live and updates metrics and charts accordingly.
   - If the checkbox is unchecked, only the static metrics are displayed.

This setup provides a **dynamic dashboard** that pulls and visualizes real-time eCommerce data, making it interactive and responsive for monitoring sales and performance metrics.

```python
## producer/streamlit/app.py
import json
import asyncio

import aiohttp
import streamlit as st
from streamlit.delta_generator import DeltaGenerator

from utils import (
    load_records,
    create_metric_items,
    generate_metrics,
    create_options_items,
    generate_charts,
)


async def generate(
    metric_placeholder: DeltaGenerator, chart_placeholder: DeltaGenerator
):
    prev_values = {"num_orders": 0, "num_order_items": 0, "total_sales": 0}
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect("ws://localhost:8000/ws") as ws:
            async for msg in ws:
                metric_values, df = load_records(json.loads(msg.json()))
                generate_metrics(
                    metric_placeholder, create_metric_items(metric_values, prev_values)
                )
                generate_charts(chart_placeholder, create_options_items(df))
                prev_values = metric_values


st.set_page_config(
    page_title="theLook eCommerce",
    page_icon="✅",
    layout="wide",
)

st.title("theLook eCommerce Dashboard")

connect = st.checkbox("Connect to WS Server")
metric_placeholder = st.empty()
chart_placeholder = st.empty()

if connect:
    asyncio.run(
        generate(
            metric_placeholder=metric_placeholder, chart_placeholder=chart_placeholder
        )
    )
else:
    generate_metrics(metric_placeholder, None)
```

## Start Dashboard

The dashboard can be started by running the Streamlit app with the command `streamlit run streamlit/app.py`. Once started, it can be accessed in a browser at *http://localhost:8501*.

![](featured.gif#center)