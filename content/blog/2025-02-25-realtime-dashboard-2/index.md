---
title: Realtime Dashboard with Streamlit and Next.js - Part 2 Streamlit Frontend
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
  - Websocket
authors:
  - JaehyeonKim
images: []
description:
---

to be updated!!!!!!!!

<!--more-->

* [Part 1 Data Producer](/blog/2025-02-18-realtime-dashboard-1)
* [Part 2 Streamlit Frontend](#) (this post)
* Part 3 Next.js Frontend

## Start Data Producer

## Streamlit Frontend

### Components

```python
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

```python
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
