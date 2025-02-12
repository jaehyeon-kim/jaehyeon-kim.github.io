---
title: Realtime Dashboard with Streamlit and Next.js - Part 3 Next.js Frontend
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
  - Websocket
authors:
  - JaehyeonKim
images: []
description:
---

to be updated!!!!!!!!

<!--more-->

* [Part 1 Data Producer](/blog/2025-02-18-realtime-dashboard-1)
* [Part 2 Streamlit Frontend](/blog/2025-02-25-realtime-dashboard-2)
* [Part 3 Next.js Frontend](#) (this post)

## Start Data Producer

## Next.js Frontend

### Components

```js
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
