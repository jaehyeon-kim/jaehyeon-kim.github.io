---
title: Realtime Dashboard with FastAPI, Streamlit and Next.js - Part 3 Next.js Dashboard
date: 2025-03-04
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
  - React
  - Next.js
  - TypeScript
  - Apache ECharts
  - WebSocket
authors:
  - JaehyeonKim
images: []
description:
---

Welcome to theLook eCommerce Dashboard, a powerful tool designed to help businesses track and analyze key metrics in real time. This dynamic dashboard provides an intuitive interface to visualize essential sales data, such as the number of orders, total sales, and more. Leveraging WebSocket technology, the dashboard seamlessly updates as new data flows in, giving users live insights into their eCommerce performance. With interactive charts and detailed metric cards, theLook empowers businesses to make data-driven decisions, optimize their operations, and stay ahead of trends—no matter where they are.

<!--more-->

* [Part 1 Data Producer](/blog/2025-02-18-realtime-dashboard-1)
* [Part 2 Streamlit Dashboard](/blog/2025-02-25-realtime-dashboard-2)
* [Part 3 Next.js Dashboard](#) (this post)

## Deploy Data Producer

The data generator and WebSocket server can be deployed using Docker Compose with the command `docker-compose -f producer/docker-compose.yml up -d`. Once started, the server can be checked with a [WebSocket client](https://github.com/lewoudar/ws/) using the command `ws listen ws://localhost:8000/ws`, and its logs can be monitored by running `docker logs -f producer`. The source code for this post can be found in this [**GitHub repository**](https://github.com/jaehyeon-kim/streaming-demos/tree/main/product-demos).

![](backend.gif#center)

## Next.js Frontend

### Components

This code defines a React component called `Metric` that displays a metric card with the following props:

- `label`: The title or name of the metric.
- `value`: The value of the metric (could represent a number or currency).
- `delta`: The change in the metric value (used to indicate increase or decrease).
- `is_currency`: A boolean flag to indicate whether the value should be formatted as a currency.

### Key Features:
- **Formatting**: The `value` is displayed with localization and a "$" sign if `is_currency` is true.
- **Delta Indicator**: An arrow icon is displayed with a color that depends on whether `delta` is positive (green), negative (red), or zero (black). The delta is shown below the value in the footer.
- **Card Layout**: The component uses `Card`, `CardHeader`, `CardBody`, `CardFooter`, and `Divider` components from NextUI for layout and styling.

The card's visual layout includes the label at the top, the formatted value in large text, and the delta change with an arrow beneath it.

```js
// nextjs/src/components/metric.tsx
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
            data-testid="stMetricDeltaIcon-Up"
            className="e14lo1l1 st-emotion-cache-1ksdj5j ex0cdmw0"
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

This code defines a set of functions and interfaces used to manage and compute metrics and options related to sales data. Here’s a detailed breakdown of its structure:

### Interfaces:

1. **MetricProps** (imported from `@/components/metric`):
   - This defines the properties for a single metric, including:
     - `label`: The label for the metric (e.g., "Number of Orders").
     - `value`: The value of the metric.
     - `delta`: The change (or delta) in the metric compared to a previous value.
     - `is_currency`: A boolean indicating whether the metric value is in currency format.

2. **Metrics**:
   - Represents the main metrics related to orders and sales:
     - `num_orders`: The total number of unique orders.
     - `num_order_items`: The total number of unique items ordered.
     - `total_sales`: The total sales revenue.

3. **Record**:
   - Represents a single record in the dataset, capturing detailed information such as:
     - `user_id`: ID of the user.
     - `age`, `gender`, `country`: User demographic and location.
     - `traffic_source`: Where the user came from (e.g., Google, Facebook).
     - `order_id`, `item_id`, `category`, `item_status`: Order and item details.
     - `sale_price`: Price of the item in the order.
     - `created_at`: Timestamp when the order was created.

### Constants:

1. **defaultMetrics**:
   - Provides a default value for the `Metrics` interface with initial values of zero for all metrics.

2. **defaultMetricItems**:
   - Defines an array of `MetricProps` with initial values set to zero. It includes metrics for:
     - Number of Orders
     - Number of Order Items
     - Total Sales (as currency)

### Functions:

1. **getMetrics(records: Record[])**:
   - This function calculates the current metrics (`num_orders`, `num_order_items`, `total_sales`) from an array of `Record` objects:
     - `num_orders`: Counts the unique `order_id` values.
     - `num_order_items`: Counts the unique `item_id` values.
     - `total_sales`: Sums up the `sale_price` of all records and rounds it.

2. **createMetricItems(currMetrics: Metrics, prevMetrics: Metrics)**:
   - This function generates an array of `MetricProps` (used to display metrics on the frontend). It calculates the change (`delta`) between the current and previous metrics for:
     - Number of Orders
     - Number of Order Items
     - Total Sales (currency)
   - It returns an array of `MetricProps`, which includes the label, value, delta, and currency flag.

3. **createOptionsItems(records: Record[])**:
   - This function creates chart configuration options for displaying revenue data:
     - The `chartCols` array contains two columns: `country` and `traffic_source`, each paired with `sale_price`.
     - For each column (`country` and `traffic_source`), it groups the records by the column value and sums the `sale_price`.
     - It sorts the data in descending order of the summed `sale_price`.
     - The function generates chart options for a bar chart with `xAxis` as the categories (e.g., countries or traffic sources) and `yAxis` as the corresponding revenue.
     - The chart is configured with tooltip options and rotated labels for better readability.

### Key Details:
- The code relies on manipulating arrays of `Record` objects to calculate summary metrics and create visual representations (charts).
- `getMetrics` and `createMetricItems` are used to calculate the current and delta metrics for display.
- `createOptionsItems` is used for creating data visualizations, particularly bar charts to display revenue by various categories (country, traffic source).

```js
import { MetricProps } from "@/components/metric";

export interface Metrics {
  num_orders: number;
  num_order_items: number;
  total_sales: number;
}

export interface Record {
  user_id: string;
  age: number;
  gender: string;
  country: string;
  traffic_source: string;
  order_id: string;
  item_id: string;
  category: string;
  item_status: string;
  sale_price: number;
  created_at: number;
}

export const defaultMetrics: Metrics = {
  num_orders: 0,
  num_order_items: 0,
  total_sales: 0,
};

export const defaultMetricItems: MetricProps[] = [
  { label: "Number of Orders", value: 0, delta: 0, is_currency: false },
  { label: "Number of Order Items", value: 0, delta: 0, is_currency: false },
  { label: "Total Sales", value: 0, delta: 0, is_currency: true },
];

export function getMetrics(records: Record[]) {
  const num_orders = [...new Set(records.map((r) => r.order_id))].length;
  const num_order_items = [...new Set(records.map((r) => r.item_id))].length;
  const total_sales = Math.round(
    records.map((r) => Number(r.sale_price)).reduce((a, b) => a + b, 0)
  );
  return {
    num_orders: num_orders,
    num_order_items: num_order_items,
    total_sales: total_sales,
  };
}

export function createMetricItems(currMetrics: Metrics, prevMetrics: Metrics) {
  const labels = [
    { label: "Number of Orders", metric: "num_orders", is_currency: false },
    {
      label: "Number of Order Items",
      metric: "num_order_items",
      is_currency: false,
    },
    { label: "Total Sales", metric: "total_sales", is_currency: true },
  ];
  return labels.map((obj) => {
    const label = obj.label;
    const value = currMetrics[obj.metric as keyof Metrics];
    const delta =
      currMetrics[obj.metric as keyof Metrics] -
      prevMetrics[obj.metric as keyof Metrics];
    const is_currency = obj.is_currency;
    return {
      label,
      value,
      delta,
      is_currency,
    };
  });
}

export function createOptionsItems(records: Record[]) {
  const chartCols = [
    { x: "country", y: "sale_price" },
    { x: "traffic_source", y: "sale_price" },
  ];
  return chartCols.map((col) => {
    // key is string but it throws the following error. Change the type to 'string | number'.
    // Argument of type 'string | number' is not assignable to parameter of type 'string'.
    // Type 'number' is not assignable to type 'string'.ts(2345)
    const recordsMap = new Map<string | number, number>();
    for (const r of records) {
      recordsMap.set(
        r[col.x as keyof Record],
        (recordsMap.get(r[col.x as keyof Record]) || 0) +
          Number(r[col.y as keyof Record])
      );
    }
    const recordsItems = Array.from(recordsMap, ([x, y]) => ({ x, y })).sort(
      (a, b) => (a.y > b.y ? -1 : 1)
    );
    const suffix = col.x
      .split("_")
      .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
      .join(" ");
    return {
      title: { text: "Revenue by ".concat(suffix) },
      yAxis: { type: "value" },
      xAxis: {
        type: "category",
        data: recordsItems.map((r) => r.x),
        axisLabel: { show: true, rotate: 75 },
      },
      series: [
        {
          data: recordsItems.map((r) => Math.round(r.y)),
          type: "bar",
          colorBy: "data",
        },
      ],
      tooltip: { trigger: "axis", axisPointer: { type: "shadow" } },
    };
  });
}
```

### Application

This React component (`Home`) implements a dashboard that displays eCommerce metrics and charts, updated via a WebSocket connection. Here's a detailed breakdown of how it works:

### State Variables:
- **`toConnect`**: A boolean to control whether to connect to the WebSocket server.
- **`currMetrics` and `prevMetrics`**: Store the current and previous metrics (such as number of orders, sales, etc.).
- **`metricItems`**: Stores the data for individual metric items (such as total sales, number of orders) that will be displayed on the dashboard.
- **`chartOptions`**: Holds the configuration for charts to visualize data.

### WebSocket:
- The component uses the `react-use-websocket` hook to establish a WebSocket connection (`ws://localhost:8000/ws`) for real-time data updates.
- The WebSocket connection can be toggled using a checkbox that sets `toConnect` to true or false.

### `useEffect` Hook:
- This hook listens for new data (`lastJsonMessage` from the WebSocket) and processes it when it arrives.
- It parses the incoming data (assumed to be a JSON array of records), updates the metrics using `getMetrics`, `createMetricItems`, and `createOptionsItems` functions.
  - **`getMetrics(records)`** computes overall metrics like number of orders, items, and total sales.
  - **`createMetricItems(currMetrics, prevMetrics)`** creates metric cards showing the current values and changes (deltas) compared to the previous state.
  - **`createOptionsItems(records)`** generates chart configurations, likely for visualizing revenue based on categories like `country` or `traffic_source`.

### Component Functions:
- **`createMetrics(metricItems)`**: Iterates over the `metricItems` array and creates `Metric` components to display metrics (like number of orders, sales).
- **`createCharts(chartOptions)`**: Iterates over the `chartOptions` array and creates `ReactECharts` components for displaying charts. Each chart is configured based on the options generated by `createOptionsItems`.

### UI Elements:
- **Checkbox for WebSocket Connection**: A checkbox labeled "Connect to WS Server" that allows the user to toggle the WebSocket connection.
- **Metric Cards**: Displays various metrics like "Number of Orders", "Total Sales", etc., based on the `metricItems` state.
- **Charts**: Displays visualizations (e.g., bar charts) based on the `chartOptions` state, showing revenue by categories like `country` or `traffic source`.

### Overall Flow:
1. The component first displays a dashboard header and a checkbox to toggle the WebSocket connection.
2. When data is received via WebSocket, it updates the metrics and charts by calculating new values and re-rendering the metrics and charts.
3. Metrics are displayed in a grid layout, followed by charts showing relevant data visualizations.

This setup allows for a dynamic dashboard that automatically updates as new data comes in via the WebSocket connection.

```js
"use client";

import { useEffect, useState } from "react";
import { Checkbox } from "@nextui-org/react";
import ReactECharts, { EChartsOption } from "echarts-for-react";
import useWebSocket from "react-use-websocket";

import Metric, { MetricProps } from "@/components/metric";
import {
  getMetrics,
  createMetricItems,
  defaultMetrics,
  defaultMetricItems,
  createOptionsItems,
} from "@/lib/processing";

export default function Home() {
  const [toConnect, toggleToConnect] = useState(false);
  const [currMetrics, setCurrMetrics] = useState(defaultMetrics);
  const [prevMetrics, setPrevMetrics] = useState(defaultMetrics);
  const [metricItems, setMetricItems] = useState(defaultMetricItems);
  const [chartOptions, setChartOptions] = useState([] as EChartsOption[]);

  const { lastJsonMessage } = useWebSocket(
    "ws://localhost:8000/ws",
    {
      share: false,
      shouldReconnect: () => true,
    },
    toConnect
  );

  useEffect(() => {
    const records = JSON.parse(lastJsonMessage as string);
    if (!!records) {
      setPrevMetrics(currMetrics);
      setCurrMetrics(getMetrics(records));
      setMetricItems(createMetricItems(currMetrics, prevMetrics));
      setChartOptions(createOptionsItems(records));
    }
  }, [lastJsonMessage]);

  const createMetrics = (metricItems: MetricProps[]) => {
    return metricItems.map((item, i) => {
      return (
        <Metric
          key={i}
          label={item.label}
          value={item.value}
          delta={item.delta}
          is_currency={item.is_currency}
        ></Metric>
      );
    });
  };

  const createCharts = (chartOptions: EChartsOption[]) => {
    return chartOptions.map((option, i) => {
      return (
        <ReactECharts
          key={i}
          className="col-span-12 md:col-span-6"
          option={option}
          style={{ height: "500px" }}
        />
      );
    });
  };

  return (
    <div>
      <div className="mt-20">
        <div className="flex m-2 justify-between items-center">
          <h1 className="text-4xl font-bold">theLook eCommerce Dashboard</h1>
        </div>
        <div className="flex m-2 mt-5 justify-between items-center mt-5">
          <Checkbox
            color="primary"
            onChange={() => toggleToConnect(!toConnect)}
          >
            Connect to WS Server
          </Checkbox>
          ;
        </div>
      </div>
      <div className="grid grid-cols-12 gap-4 mt-5">
        {createMetrics(metricItems)}
      </div>
      <div className="grid grid-cols-12 gap-4 mt-5">
        {createCharts(chartOptions)}
      </div>
    </div>
  );
}
```

## Start Dashboard

The dashboard can be started the command `pnpm dev`. Once started, it can be accessed in a browser at *http://localhost:3000*.

![](featured.gif#center)