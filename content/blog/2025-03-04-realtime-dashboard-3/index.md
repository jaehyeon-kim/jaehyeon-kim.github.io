---
title: Next.js Dashboard - Realtime Dashboard with FastAPI, Streamlit and Next.js Part 3
date: 2025-03-04
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
  - Next.js
  - React
  - WebSocket
description: Next.js and React with Apache ECharts show the same live order and revenue metrics, reading from the FastAPI WebSocket server in the browser.
---

A real-time monitoring dashboard connects to the WebSocket server from [Part 1](/blog/2025-02-18-realtime-dashboard-1) to continuously fetch and visualize key metrics such as **order counts**, **sales data**, and **revenue by traffic source and country**. With interactive bar charts and dynamic metrics, users can monitor sales trends and other critical business KPIs in real-time. In this post, we build it using [Next.js](https://nextjs.org/), a React framework that supports server-side rendering, static site generation, and full-stack capabilities with built-in performance optimizations. It is similar to the *Streamlit* app we developed in [Part 2](/blog/2025-02-25-realtime-dashboard-2).  

<!--more-->

* [Part 1 Data Producer](/blog/2025-02-18-realtime-dashboard-1)
* [Part 2 Streamlit Dashboard](/blog/2025-02-25-realtime-dashboard-2)
* [Part 3 Next.js Dashboard](#) (this post)

## Next.js Frontend

![The Next.js dashboard reads the recent order items from the WebSocket server, which reads them from PostgreSQL](part-3.png#center "Architecture")

The Next.js dashboard processes and displays real-time *theLook eCommerce data*. It connects to the WebSocket server using the [*React useWebSocket*](https://github.com/robtaussig/react-use-websocket) package, while the UI is styled with [HeroUI (formerly NextUI)](https://www.heroui.com/) and [Tailwind CSS](https://tailwindcss.com/). Visualizations are powered by [Apache ECharts](https://github.com/hustcc/echarts-for-react). The source code for this post is available in the **live-dashboard** folder of the [**benchtop**](https://github.com/jaehyeon-kim/benchtop/tree/main/live-dashboard) GitHub repository.

### Metric Component

We use a React component called `Metric` that displays a metric card with the following props:

- `label`: The title or name of the metric.
- `value`: The value of the metric (could represent a number or currency).
- `delta`: The change in the metric value (used to indicate increase or decrease).
- `is_currency`: A boolean flag to indicate whether the value should be formatted as a currency.

The card's visual layout includes the label at the top, the formatted value in large text, and the delta change with an arrow beneath it.

```jsx
// live-dashboard/nextjs/src/components/metric.tsx
"use client";

import {
  Card,
  CardHeader,
  CardBody,
  Divider,
  CardFooter,
} from "@nextui-org/react";

export interface MetricProps {
  label: string;
  value: number;
  delta: number;
  is_currency: boolean;
}

export default function Metric({
  label,
  value,
  delta,
  is_currency,
}: MetricProps) {
  const formatted_value = is_currency
    ? "$ ".concat(value.toLocaleString())
    : value.toLocaleString();
  const arrowColor = delta == 0 ? "black" : delta > 0 ? "green" : "red";
  return (
    <div className="col-span-12 md:col-span-4">
      <Card>
        <CardHeader>{label}</CardHeader>
        <CardBody>
          <h1 className="text-4xl font-bold">{formatted_value}</h1>
        </CardBody>
        <Divider />
        <CardFooter>
          <svg
            height={25}
            viewBox="0 0 24 24"
            aria-hidden="true"
            focusable="false"
            fill={arrowColor}
            xmlns="http://www.w3.org/2000/svg"
            color="inherit"
          >
            <path fill="none" d="M0 0h24v24H0V0z"></path>
            <path d="M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8-8 8z"></path>
          </svg>
          <h1 className="text-xl">{delta.toLocaleString()}</h1>
        </CardFooter>
      </Card>
    </div>
  );
}
```

### Data Processing Utility

Since I have yet to find an effective data manipulation library comparable to Python's Pandas, data processing is handled using custom objects and functions. The code primarily operates on arrays of `Record`s to compute sales metrics and generate visual representations. The `getMetrics` and `createMetricItems` functions are used to calculate current/delta metrics and construct an array of `MetricProp`s that can be added to the *Metric* component. Also, the `createOptionsItems` function is responsible for generating data visualizations, specifically bar charts that show revenue by categories such as country and traffic source.

```jsx
// live-dashboard/nextjs/src/lib/processing.ts
// Turns the WebSocket's records into metric cards and chart options, with no React.
// The Streamlit dashboard does the same in sales/dashboard/metrics.py.
import { EChartsOption } from "echarts-for-react";

import { MetricProps } from "@/components/metric";

export interface Record {
  user_id: string;
  age: number;
  gender: string;
  country: string;
  traffic_source: string;
  order_id: string;
  item_id: string;
  category: string;
  cost: number;
  item_status: string;
  sale_price: number;
  created_at: string;
}

export interface Metrics {
  num_orders: number;
  num_order_items: number;
  total_sales: number;
}

const LABELS: { [K in keyof Metrics]: string } = {
  num_orders: "Number of Orders",
  num_order_items: "Number of Order Items",
  total_sales: "Total Sales",
};
const CHARTS = { country: "Country", traffic_source: "Traffic Source" }; // revenue grouped by

export const defaultMetrics: Metrics = { num_orders: 0, num_order_items: 0, total_sales: 0 };

export function getMetrics(records: Record[]): Metrics {
  return {
    num_orders: new Set(records.map((r) => r.order_id)).size,
    num_order_items: new Set(records.map((r) => r.item_id)).size,
    total_sales: Math.round(records.reduce((sum, r) => sum + r.sale_price, 0)),
  };
}

export function createMetricItems(current: Metrics, previous: Metrics): MetricProps[] {
  return (Object.keys(LABELS) as (keyof Metrics)[]).map((key) => ({
    label: LABELS[key],
    value: current[key],
    delta: current[key] - previous[key],
    is_currency: key === "total_sales",
  }));
}

export function createOptionsItems(records: Record[]): EChartsOption[] {
  return (Object.keys(CHARTS) as (keyof typeof CHARTS)[]).map((column) => {
    const revenue = new Map<string, number>();
    for (const r of records) revenue.set(r[column], (revenue.get(r[column]) ?? 0) + r.sale_price);
    const bars = [...revenue].sort((a, b) => b[1] - a[1]);
    return {
      title: { text: `Revenue by ${CHARTS[column]}` },
      grid: { containLabel: true }, // room for the rotated axis labels
      xAxis: { type: "category", data: bars.map(([name]) => name), axisLabel: { rotate: 75 } },
      yAxis: { type: "value" },
      series: [{ type: "bar", colorBy: "data", data: bars.map(([, value]) => Math.round(value)) }],
      tooltip: { trigger: "axis", axisPointer: { type: "shadow" } },
    };
  });
}
```

### Application

The main component builds a real-time eCommerce dashboard that connects to a WebSocket server at `ws://127.0.0.1:8000/ws` to fetch and display live data. A hook, `useDashboard`, uses the *React useWebSocket* package (`react-use-websocket`) to manage the WebSocket connection, and whenever new data is received, it updates the state with the latest metrics and chart options. The data processing is handled by helper functions (`getMetrics`, `createMetricItems`, and `createOptionsItems`), which compute summary metrics and prepare visualization data. The UI dynamically updates to display key business metrics using the *Metric* component and interactive bar charts powered by *Apache ECharts* (`echarts-for-react`). A checkbox allows users to toggle the WebSocket connection on or off, giving them control over real-time updates.

```jsx
// live-dashboard/nextjs/src/lib/useDashboard.ts
import { useEffect, useRef, useState } from "react";
import { EChartsOption } from "echarts-for-react";
import useWebSocket from "react-use-websocket";

import { MetricProps } from "@/components/metric";
import { createMetricItems, createOptionsItems, defaultMetrics, getMetrics, Record } from "@/lib/processing";

// Follows the WebSocket while `connected`, and turns each message into cards and charts.
export default function useDashboard(url: string, connected: boolean) {
  const [metricItems, setMetricItems] = useState<MetricProps[]>(createMetricItems(defaultMetrics, defaultMetrics));
  const [chartOptions, setChartOptions] = useState<EChartsOption[]>([]);
  const previous = useRef(defaultMetrics);
  const { lastJsonMessage } = useWebSocket<Record[]>(url, { share: false, shouldReconnect: () => true }, connected);

  useEffect(() => {
    if (!lastJsonMessage) return;
    const metrics = getMetrics(lastJsonMessage);
    setMetricItems(createMetricItems(metrics, previous.current));
    setChartOptions(createOptionsItems(lastJsonMessage));
    previous.current = metrics;
  }, [lastJsonMessage]);

  return { metricItems, chartOptions };
}
```

```jsx
// live-dashboard/nextjs/src/app/page.tsx
"use client";

import { useState } from "react";
import { Checkbox } from "@nextui-org/react";
import ReactECharts from "echarts-for-react";

import Metric from "@/components/metric";
import useDashboard from "@/lib/useDashboard";

export default function Home() {
  const [connected, setConnected] = useState(false);
  const { metricItems, chartOptions } = useDashboard("ws://127.0.0.1:8000/ws", connected);

  return (
    <div>
      <div className="mt-20">
        <div className="flex m-2 justify-between items-center">
          <h1 className="text-4xl font-bold">theLook eCommerce Dashboard</h1>
        </div>
        <div className="flex m-2 mt-5 justify-between items-center">
          <Checkbox color="primary" onChange={() => setConnected(!connected)}>
            Connect to WS Server
          </Checkbox>
        </div>
      </div>
      <div className="grid grid-cols-12 gap-4 mt-5">
        {metricItems.map((item, i) => (
          <Metric key={i} {...item} />
        ))}
      </div>
      <div className="grid grid-cols-12 gap-4 mt-5">
        {chartOptions.map((option, i) => (
          <ReactECharts key={i} className="col-span-12 md:col-span-6" option={option} style={{ height: "500px" }} />
        ))}
      </div>
    </div>
  );
}
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

The dashboard can be started in development mode as shown below. Once started, it can be accessed in a browser at *http://127.0.0.1:3000*.

```bash
## install pnpm if not done
# https://pnpm.io/installation

## install dependent packages
$ cd nextjs
$ pnpm install

## start the app
$ pnpm dev
```

![Next.js dashboard with order, item and sales cards above bar charts of revenue by country and by traffic source](nextjs-dashboard.png#center "Next.js dashboard connected to the WebSocket server")