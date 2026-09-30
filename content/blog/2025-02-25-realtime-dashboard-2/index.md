---
title: Streamlit Dashboard - Realtime Dashboard with FastAPI, Streamlit and Next.js Part 2
date: 2025-02-25
draft: false
featured: false
comment: true
toc: true
series:
  - Realtime Dashboard with FastAPI, Streamlit and Next.js
categories:
  - Development
tags: 
  - Apache ECharts
  - Python
  - Streamlit
  - WebSocket
description: Streamlit and Apache ECharts draw a live sales dashboard that reads order counts and revenue by country from a FastAPI WebSocket server.
---

A real-time monitoring dashboard is developed using [Streamlit](https://streamlit.io/), an open-source Python framework that allows data scientists and AI/ML engineers to create interactive data apps. The app connects to the WebSocket server we developed in [Part 1](/blog/2025-02-18-realtime-dashboard-1) and continuously fetches data to visualize key metrics such as **order counts**, **sales data**, and **revenue by traffic source and country**. With interactive bar charts and dynamic metrics, users can monitor sales trends and other important business KPIs in real-time.

<!--more-->

* [Part 1 Data Producer](/blog/2025-02-18-realtime-dashboard-1)
* [Part 2 Streamlit Dashboard](#) (this post)
* [Part 3 Next.js Dashboard](/blog/2025-03-04-realtime-dashboard-3)

## Streamlit Frontend

![The Streamlit dashboard reads the recent order items from the WebSocket server, which reads them from PostgreSQL](part-2.png#center "Architecture")

This Streamlit dashboard is designed to process and display real-time *theLook eCommerce data* using plain Python for data manipulation, Streamlit's built-in *metric* component for KPIs, and *Apache ECharts* for visualizations. The source code for this post can be found in the **live-dashboard** folder of the [**benchtop**](https://github.com/jaehyeon-kim/benchtop/tree/main/live-dashboard) GitHub repository.

### Components

The data processing logic is managed by functions in `sales/dashboard/metrics.py`, and the dashboard components are drawn by `sales/dashboard/streamlit_app.py`. Below are the details of those functions.

1. Calculating Metrics:
   - The `metrics()` function accepts a list of records, as the WebSocket server sends them.
   - Key metrics like the **number of orders**, **number of order items**, and **total sales** are calculated from the records and returned for display, with the total sales rounded to whole dollars.

2. Generating Metrics:
   - The `metric_cards()` function creates a list of dictionaries containing metrics and their respective changes (`delta`), comparing the current and previous values of **orders**, **order items**, and **total sales**.
   - The `_draw()` function in `streamlit_app.py` takes the metric cards and displays them in Streamlit’s **metric components** within the `cards_area` container. It uses a column layout to show the metrics side-by-side.

3. Creating Chart Options:
   - The `revenue_charts()` function generates configuration data for bar charts that display **revenue by country** and **revenue by traffic source**. 
   - It groups the records by **country** and **traffic source**, sums the **sale_price** for each, and sorts it in descending order. 
   - **ECharts options** are defined for each chart with titles and axis settings, and each bar takes its own colour. The charts are configured to show **tooltips** when hovering over the bars.

4. Displaying Charts:
   - The `_draw()` function also takes the **ECharts options** and renders each chart within the `charts_area` container using the `st_echarts` component of the [streamlit-echarts](https://pypi.org/project/streamlit-echarts/) package.
   - Each chart is placed in its own column, with dynamic layout adjustments based on the number of charts being displayed. The charts are rendered with a fixed height of **500px**.

```python
# live-dashboard/sales/dashboard/metrics.py
"""Turns the WebSocket's records into the dashboard's metric cards and chart options.

The Next.js dashboard does the same in `nextjs/src/lib/processing.ts`.
"""

from collections import defaultdict

LABELS = {
    "num_orders": "Number of Orders",
    "num_order_items": "Number of Order Items",
    "total_sales": "Total Sales",
}
CHARTS = {
    "country": "Country",
    "traffic_source": "Traffic Source",
}  # revenue grouped by


def metrics(records: list[dict]) -> dict[str, int]:
    """
    Counts the orders and order items, and adds up the sales.

    Args:
        records (list[dict]): The order items, from the WebSocket.

    Returns:
        dict[str, int]: `num_orders`, `num_order_items` and `total_sales`, in dollars.
    """
    return {
        "num_orders": len({r["order_id"] for r in records}),
        "num_order_items": len({r["item_id"] for r in records}),
        "total_sales": round(sum(r["sale_price"] for r in records)),
    }


def metric_cards(current: dict[str, int], previous: dict[str, int]) -> list[dict]:
    """
    Builds the metric cards, each with its change since the last update.

    Args:
        current (dict[str, int]): The metrics now.
        previous (dict[str, int]): The metrics at the last update.

    Returns:
        list[dict]: Each card's `label`, `value` and `delta`.
    """
    return [
        {
            "label": label,
            "value": f"$ {current[k]}" if k == "total_sales" else current[k],
            "delta": current[k] - previous[k],
        }
        for k, label in LABELS.items()
    ]


def revenue_charts(records: list[dict]) -> list[dict]:
    """
    Builds the ECharts options of revenue by country and by traffic source.

    Args:
        records (list[dict]): The order items, from the WebSocket.

    Returns:
        list[dict]: One bar chart's options per grouping, largest revenue first.
    """
    charts = []
    for column, title in CHARTS.items():
        revenue: dict[str, float] = defaultdict(float)
        for r in records:
            revenue[r[column]] += r["sale_price"]
        bars = sorted(revenue.items(), key=lambda kv: kv[1], reverse=True)
        charts.append(
            {
                "title": {"text": f"Revenue by {title}"},
                "grid": {"containLabel": True},  # room for the rotated axis labels
                "xAxis": {
                    "type": "category",
                    "data": [k for k, _ in bars],
                    "axisLabel": {"rotate": 75},
                },
                "yAxis": {"type": "value"},
                "series": [
                    {
                        "type": "bar",
                        "colorBy": "data",
                        "data": [round(v) for _, v in bars],
                    }
                ],
                "tooltip": {"trigger": "axis", "axisPointer": {"type": "shadow"}},
            }
        )
    return charts
```

### Application

The dashboard connects to the **WebSocket server** to fetch and display real-time *theLook eCommerce* data. Here's a detailed breakdown of its functionality:

1. WebSocket Connection:
   - The `_follow()` function is an **asynchronous** task that establishes a connection to a WebSocket server (`ws://127.0.0.1:8000/ws`) using an asynchronous HTTP client by the [aiohttp](https://pypi.org/project/aiohttp/) package. It listens for incoming messages from the server, which contain the eCommerce data.
   - As each message is received, the function reads its list of records and computes key metrics using the `metrics()` function.

2. Generating and Displaying Metrics:
   - The `metric_cards()` function calculates and prepares key metrics (such as **number of orders**, **order items**, and **total sales**) along with the delta (changes) from the previous values.
   - The `_draw()` function updates the Streamlit dashboard by displaying these metrics in the `cards_area`.

3. Creating and Displaying Charts:
   - The `revenue_charts()` function processes the data and generates configuration options for bar charts, displaying **revenue by country** and **traffic source**.
   - The `_draw()` function renders the charts in the `charts_area` container, using **ECharts** for interactive data visualizations.

4. Real-time Updates:
   - The loop continuously listens for new data from the WebSocket server. As data is received, it updates both the metrics and charts in real-time.

5. User Interface:
   - The app sets a wide layout with the title **"theLook eCommerce Dashboard"**. 
   - A checkbox (`Connect to WS Server`) lets the user choose whether to connect to the WebSocket server. When checked, the dashboard fetches data live and updates metrics and charts accordingly.
   - If the checkbox is unchecked, only the static metrics are displayed.

This setup provides a **dynamic dashboard** that pulls and visualizes real-time eCommerce data, making it interactive and responsive for monitoring sales and performance metrics.

```python
# live-dashboard/sales/dashboard/streamlit_app.py
"""The Streamlit dashboard: metric cards and revenue charts, updated from the WebSocket.

Run: python -m streamlit run sales/dashboard/streamlit_app.py
"""

import asyncio

import aiohttp
import streamlit as st
from streamlit_echarts import st_echarts

from sales.core.config import WS_URL
from sales.dashboard.metrics import LABELS, metric_cards, metrics, revenue_charts


def _draw(cards: list[dict], charts: list[dict], cards_area, charts_area) -> None:
    """Replaces the cards and charts on the page."""
    with cards_area.container():
        for col, card in zip(st.columns(len(cards)), cards):
            col.metric(**card)
    if not charts:  # before the first message
        return
    with charts_area.container():
        for col, options in zip(st.columns(len(charts)), charts):
            with col:
                st_echarts(options=options, height="500px")


async def _follow(cards_area, charts_area) -> None:
    """Redraws the page for every message the WebSocket sends."""
    previous = dict.fromkeys(LABELS, 0)
    async with aiohttp.ClientSession() as session, session.ws_connect(WS_URL) as ws:
        async for message in ws:
            records = message.json()
            current = metrics(records)
            _draw(
                metric_cards(current, previous),
                revenue_charts(records),
                cards_area,
                charts_area,
            )
            previous = current


st.set_page_config(page_title="theLook eCommerce", layout="wide")
st.title("theLook eCommerce Dashboard")
connect = st.checkbox("Connect to WS Server")
cards_area, charts_area = st.empty(), st.empty()
if connect:
    asyncio.run(_follow(cards_area, charts_area))
else:
    _draw(metric_cards(*[dict.fromkeys(LABELS, 0)] * 2), [], cards_area, charts_area)
```

## Deployment

### Data Producer and WebSocket Server

As discussed in [Part 1](/blog/2025-02-18-realtime-dashboard-1), PostgreSQL is started with `odctl up postgres`, and the data generator and WebSocket server are started with `python -m sales.simulation.run` and `uvicorn sales.api.server:app --host 127.0.0.1 --port 8000`, each in its own terminal. Once started, the server can be checked with the WebSocket client of the [websockets](https://websockets.readthedocs.io/) package by executing `python -m websockets ws://127.0.0.1:8000/ws`, and its logs are printed in its terminal.

The client prints each message the server sends: a list of the order items of the last five minutes, here 39 records in the first message.

```bash
python -m websockets ws://127.0.0.1:8000/ws
```

```text
Connected to ws://127.0.0.1:8000/ws.
< [{"user_id":"427f5544-f594-4127-826e-912dc0dd970e","age":40,"gender":"M","country":"China","traffic_source":"Search","order_id":"e8c140bd-087a-4dfe-ac01-29f40a36a27e","item_id":"40deff28-0310-49ed-b11b-fdf0a3dabb24","category":"Active","cost":24.7,"item_status":"Shipped","sale_price":55.04,"created_at":"2026-09-30T13:57:06.948553+00:00"}, ...]
```

The server logs how many records it sends every five seconds:

```text
INFO:     Started server process [...]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     127.0.0.1:54478 - "WebSocket /ws" [accepted]
INFO:     connection open
INFO:     Sending 39 records
INFO:     Sending 54 records
INFO:     Sending 67 records
```

### Frontend Dashboard

The dashboard can be started by running the Streamlit app as shown below. Once started, it can be accessed in a browser at *http://127.0.0.1:8501*.

```bash
## create and activate a virtual environment
# https://docs.astral.sh/uv/
$ uv venv
$ source .venv/bin/activate

## install pip packages
(.venv) $ uv pip install -r requirements.txt

## start the app
(.venv) $ python -m streamlit run sales/dashboard/streamlit_app.py
```

![Streamlit dashboard with order, item and sales cards above bar charts of revenue by country and by traffic source](streamlit-dashboard.png#center "Streamlit dashboard connected to the WebSocket server")