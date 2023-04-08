---
title: Shiny to Vue.js
date: 2018-05-26
draft: false
featured: false
draft: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - API development with R
categories:
  - Web Development
tags: 
  - R
  - Shiny
  - JavaScript
  - Vue.js
authors:
  - JaehyeonKim
images: []
---

In the [last post](/blog/2018-05-19-asyn-shiny-and-its-limitation), the async feature of Shiny was discussed. Although it is a remarkable step forward to web development in R, it is not to the full extent that a Javascript application can bring. In fact, (long running) requests of a user (or session) are not impacted by those of other users (or sessions) but, for a given user, all requests are handled sequentially. On the other hand, it is not the case for a Javascript-backed app where all requests are processed asynchronously.

Although Javascript helps develop a more performant web app, for a Shiny developer, the downside is that key features that Shiny provides are no longer available. Some of them are built-in data binding, event handling and state management. For example, think about what `reactive*()` and `observe*()` do in a Shiny app. Although it is possible to implement those with plain Javascript or JQuery, it can be *problemsome* due to the aysnc nature of Javascript (eg [Callback Hell](http://callbackhell.com/)) or it may be ending up with a slow app (eg [Why do developers think the DOM is slow?](https://www.reddit.com/r/javascript/comments/6115ay/why_do_developers_think_the_dom_is_slow/)).

Javascript frameworks ([Angular](https://angularjs.org/), [React](https://reactjs.org/) and [Vue](https://vuejs.org/)) support such key features effectively. Also they help avoid those development issues, together with the recent [Javascript standard](https://www.quora.com/What-is-ES6). In this post, it'll be demonstrated how to render htmlwidgets in a Vue application as well as replacing *htmlwidgets* with native JavaScript libraries.

## What is Vue?

According to the [project website](https://vuejs.org/v2/guide/),

>  Vue (pronounced /vjuː/, like view) is a *progressive framework for building user interfaces*. Unlike other monolithic frameworks, Vue is designed from the ground up to be incrementally adoptable. The core library is focused on the view layer only, and is easy to pick up and integrate with other libraries or existing projects. On the other hand, Vue is also perfectly capable of powering sophisticated *Single-Page Applications* when used in combination with [modern tooling](https://vuejs.org/v2/guide/single-file-components.html) and [supporting libraries](https://github.com/vuejs/awesome-vue#components--libraries).

Some of the key features mentioned earlier are supported in the core library.

* [data binding](https://vuejs.org/v2/guide/forms.html)
* [event handling](https://vuejs.org/v2/guide/events.html)

And the other by an official library.

* [state management](https://vuejs.org/v2/guide/state-management.html)

And even more

* [routing](https://vuejs.org/v2/guide/routing.html)

*Vue* is taken here among the popular Javascript frameworks because it is *simpler to get jobs done and easier to learn*. See [this article](https://belitsoft.com/front-end-development-services/react-vs-angular) for a quick comparison.

## Building Vue Apps
### Vue Setup

Prerequisites of building a vue app are

* [_Node.js_](https://nodejs.org/en/)
    + Javascript runtime built on Chrome's V8 JavaScript engine
    + version >=6.x or 8.x (preferred)
* [_npm_](https://www.npmjs.com/)
    + package manager for Javascript and software registry
    + version 3+
    + installed with _Node.js_
* [_Git_](https://git-scm.com/)
* [_vue-cli_](https://github.com/vuejs/vue-cli/tree/master)
    + a simple CLI for scaffolding Vue.js projects
    + provides templates and _webpack-simple_ is used for the apps of this post
    + install globally - `npm install -g vue-cli`
+ [_Yarn_](https://github.com/yarnpkg/yarn)
    + fast, reliable and secure dependency management tool
    + used instead of _npm_
    + install globally - `npm install -g yarn`

The apps can be found in _vue-htmlwidgets_ and _vue-native_ folders of this [**GitHub repository**](https://github.com/jaehyeon-kim/more-thoughts-on-shiny). They are built with [webpack](https://webpack.js.org/) and can be started as following.

```bash
cd path-to-folder
yarn install
npm run dev
```
### Libraries for the Apps
#### Common libraries

* _User Interface_
    + [_Vuetify_](https://vuetifyjs.com/en/) - Although [Bootstrap](https://getbootstrap.com/docs/3.3/javascript/) is popular for user interface, I find most UI libraries that rely on *Bootstrap* also depend on *JQuery*. And it is possible the *JQuery* for *htmlwidgets* is incompatible with those for the UI libraries. Therefore _Vuetify_ is used instead, which is inspired by [Material Design](https://material.io/design/).
* _HTTP request_
    + [_axios_](https://github.com/axios/axios) - Promise based HTTP client for the browser and node.js

#### For _vue-native_
* _state management_
    + [_Vuex_](https://vuex.vuejs.org/) - _Vuex_ is a state management pattern + library for Vue.js applications. It serves as a centralized store for all the components in an application, with rules ensuring that the state can only be mutated in a predictable fashion.
* _data table_
    + Vuetify - The built-in data table component of _Vuetify_ is used.
+ _plotly_
    + _plotly_ - official library
    + _@statnett/vue-plotly_ - _plotly_ as a vue component
    + _ify-loader_ and _transform-loader_ - for building with _webpack_
+ _highcharts_
    + _highcharts_ - official library
    + _highcharts-vue_ - _highcharts_ as vue components

### Render Htmlwidgets
#### index.html
The entry point of the app is _index.html_ and _htmlwidgets_ dependencies need to be included in _head_ followed by material fonts and icons. 3 components are created in `src/components` - _DataTable.vue_, _Highchart.vue_ and _Plotly.vue_. These components are bundled into _build.js_ and sourced by the app.

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Vue - htmlwidgets</title>
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!-- necessary to control htmlwidgets -->
    <script src="/public/htmlwidgets/htmlwidgets.js"></script>
    <!-- need a shared JQuery lib -->
    <script src="/public/shared/jquery.min.js"></script>
    <!-- DT -->
    <script src="/public/datatables/datatables.js"></script>
    ... more DT dependencies
    <!-- highchater -->
    <script src="/public/highcharter/lib/proj4js/proj4.js"></script>
    ... more highcharts dependencies
    <script src="/public/highcharter/highchart.js"></script>
    <!-- plotly -->
    <script src="/public/plotly/plotly.js"></script>
    ... more plotly dependencies
    <!-- crosstalk -->
    <script src="/public/crosstalk/js/crosstalk.min.js"></script>
    ... more crosstalk depencencies
    <!-- bootstrap, etc -->
    <script src="/public/shared/bootstrap/js/bootstrap.min.js"></script>
    ... more bootstrap, etc depencencies
    <!-- vuetify -->
    <link href='https://fonts.googleapis.com/css?family=Roboto:300,400,500,700|Material+Icons' rel="stylesheet" type="text/css">
  </head>
  <body>
    <div id="app"></div>
    <script src="./dist/build.js"></script>
  </body>
</html>
```

#### Components
The widgets are constructed as [single file components](https://vuejs.org/v2/guide/single-file-components.html). 
The button (_update table_) listens on a button click event and it'll trigger `update()` defined in the _script_ of the component. Note **v-html** directive. This directive allows to render raw HTML. 

Recall that the body of a *htmlwidgets* object is

* div - widget container and element
* script - _application/json_ for widget data
* script - _application/htmlwidget-sizing_ for widget size

And `/widget` resource of the API renders all of those if **html** is specified as _type_. 

All the HTML elements is updated in this Vue application (*type = html*) while only the  _application/json_ script is appended/updated in the Javascript application (*type = src*).

```html
<template>
    <v-layout>
        <v-flex xs12 sm6 offset-sm2>
            <v-card>
                <v-card-media height="350px">
                    <v-container>
                        <v-layout row wrap justify-center>
                            <div v-if="!isLoading" v-html="dat"></div>
                        </v-layout>
                    </v-container>                    
                </v-card-media>
                <v-card-actions>
                    <v-container>
                        <v-layout row wrap justify-center>                        
                            <v-btn 
                                @click="update"
                                color="primary"
                            >update table</v-btn>
                            <div v-if="isLoading">
                                <v-progress-circular indeterminate color="info"></v-progress-circular>
                            </div>                        
                        </v-layout>
                    </v-container>
                </v-card-actions>
            </v-card>
        </v-flex>
    </v-layout>
</template>
```

Here the HTTP request is made with *axios*. The element is set to *null* at the beginning and updated by the output of the API followed by executing `window.HTMLWidgets.staticRender()`.

```js
<script>
import axios from 'axios'

export default {
    data: () => ({
        dat: null,
        isLoading: false
    }),
    methods: {
        update() {
            this.dat = null
            this.isLoading = true

            let params = { element_id: 'dt_out', type: 'html' }
            axios.post('http://[hostname]:8000/widget', params)
                .then(res => {
                    this.dat = res.data.replace('width:960px;', 'width:100%')
                    console.log(this.dat)
                    setTimeout(function() {
                        window.HTMLWidgets.staticRender()
                    }, 500)
                    this.isLoading = false
                })
                .catch(err => {
                    this.isLoading = false
                    console.log(err)
                })
        }
    }
}
</script>
```

#### Layout
The application layout is setup in `./src/App.vue` where the individual components are imported into content.

```html
<template>
  <v-app>
    <v-toolbar dense color="light-blue" dark fixed app>
      <v-toolbar-title>
          Vue - htmlwidgets
      </v-toolbar-title>
    </v-toolbar>
    <v-content>
      <app-data-table></app-data-table>
      <app-high-chart></app-high-chart>
      <app-plotly></app-plotly>
    </v-content>    
  </v-app>
</template>

<script>
import DataTable from './components/DataTable.vue'
import HighChart from './components/HighChart.vue'
import Plotly from './components/Plotly.vue'

export default {
    components: {
      appDataTable: DataTable,
      appHighChart: HighChart,
      appPlotly: Plotly
    }
}
</script>
```

The screen shot of the app is shown below.

![](vue-htmlwidgets.png#center)

### Native Libraries instead of Htmlwidgets
If an app doesn't rely on *htmlwidgets*, it only requires data to create charts and tables. The API has `/hdata` resource to return the iris data. Here the scenario is the iris data will be pulled at the beginning and 10 records are selected randomly when a user clicks a button, resulting in updating components. Note one of the key benefits of this structure is that components can communicate with each other - see what [crosstalk](https://rstudio.github.io/crosstalk/) is aimed for.

#### index.html
The entry point of the app becomes quite simple without *htmlwidgets* dependency.

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Vue - native</title>
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href='https://fonts.googleapis.com/css?family=Roboto:300,400,500,700|Material+Icons' rel="stylesheet" type="text/css">
  </head>
  <body>
    <div id="app"></div>
    <script src="./dist/build.js"></script>
  </body>
</html>
```

#### State Management
Normally a *Vue* app has multiple components so that it is important to keep changes in sync across components. Although *Vue* supports *custom events* and *event bus*, I find state management with [*Vuex*](https://vuex.vuejs.org/) is more straightforward (and better for larger apps).

In the **store** (`./src/store.js`), there are 3 **state** properties.

+ *rawData* - iris data
+ *vizData* - randomly selected records 
+ *isLoading* - indicator if data request is completed 

These *state* properties can be accessed by **getters** and modified by **mutations**. While *mutations* are synchronous, **actions** can be asynchronous. Therefore *dispatch*ing *actions* is better for something that requires some time. In this example, the HTTP request that returns the iris data is performed by *dispatch*ing `getRawData()` and, on success, the following *mutation*s are *commt*ted.

* getRawData
* updateVisData
* toggleIsLoading

```js
import Vue from 'vue'
import Vuex from 'vuex'

import axios from 'axios'
axios.defaults.baseURL = 'http://[hostname]:8000'

Vue.use(Vuex)

export default new Vuex.Store({
    state: {
        rawData: [],
        visData: [],
        isLoading: false
    },
    getters: {
        rawData (state) {
            return state.rawData
        },
        visData (state) {
            return state.visData
        },
        isLoading (state) {
            return state.isLoading
        }
    },
    mutations: {
        getRawData (state, payload) {
            state.rawData = payload
        },
        updateVisData (state) {
            state.visData = state.rawData.sort(() => .5 - Math.random()).slice(0, 10)
        },
        toggleIsLoading (state) {
            state.isLoading = !state.isLoading
        }
    },
    actions: {
        getRawData ({ commit }) {
            commit('toggleIsLoading')

            axios.post('/hdata')
                .then(res => {
                    commit('getRawData', res.data)
                    commit('updateVisData')
                    commit('toggleIsLoading')
                })
                .catch(err => {
                    console.log('error')
                    commit('toggleIsLoading')
                    console.log(err)
                })
        }
    }
})
```

#### Components
Here the source looks quite different from the *DT* object because it's created by the built-in data table component of *Vuetify* - the other 2 compoents look rather similar. The headers of the table is predefined as *data* property while the records (*visData*) are obtained from the store - it keeps in sync as a [computed property](https://v1.vuejs.org/guide/computed.html).

```html
<template>
  <v-data-table
    :headers="headers"
    :items="visData"
    class="elevation-1"
  >
    <template slot="items" slot-scope="props">
      <td class="text-xs-right">{{ props.item.SepalLength }}</td>
      <td class="text-xs-right">{{ props.item.SepalWidth }}</td>
      <td class="text-xs-right">{{ props.item.PetalLength }}</td>
      <td class="text-xs-right">{{ props.item.PetalWidth }}</td>
      <td class="text-xs-right">{{ props.item.Species }}</td>
    </template>
    <template slot="pageText" slot-scope="props">
        Lignes {{ props.pageStart }} - {{ props.pageStop }} of {{ props.itemsLength }}
    </template>
  </v-data-table>
</template>

<script>
export default {
    data () {
        return {
            headers: [
                { text: 'Sepal Length', value: 'SepalLength'},
                { text: 'Sepal Width', value: 'SepalWidth'},
                { text: 'Petal Length', value: 'PetalLength'},
                { text: 'Petal Width', value: 'PetalWidth'},
                { text: 'Species', value: 'Species'}
            ]
        }
    },
    computed: {
        visData() {
            return this.$store.getters['visData']
        }
    }
}
</script>
```

#### Layout
Instead of requesting individual *htmlwidgets* objects, charts/table are created by individual components. Also the components are updated by clicking the button. The conditional directives (*v-if* and *v-else*) controls which to render depending on the value of *isLoading*.

```html
<template>
  <v-app>
    <v-toolbar dense color="light-blue" dark fixed app>
      <v-toolbar-title>
          Vue - native
      </v-toolbar-title>
    </v-toolbar>
    <v-content>      
      <div v-if="isLoading" class="centered">
          <v-progress-circular 
            indeterminate color="info"
            :size="100"
            :width="10"
          ></v-progress-circular>
      </div>
      <div v-else>
        <v-btn @click="update">update data</v-btn>
        <v-container fluid>
          <v-layout row wrap>
            <v-flex xs12 sm12 md6>
              <div style="display: inline-block;">
                <app-data-table></app-data-table>
              </div>            
            </v-flex>
            <v-flex xs12 sm12 md6>
              <div style="display: inline-block;">
                <app-highchart></app-highchart>
              </div>            
            </v-flex>
            <v-flex xs12 sm12 md6>
              <div style="display: inline-block;">
                <app-plotly></app-plotly>
              </div>            
            </v-flex>
          </v-layout>
        </v-container>      
      </div>
    </v-content>    
  </v-app>
</template>
```

Upon creation of the component (`created()`),  `getRawData()` is *dispatch*ed. While the request is being processed, the computed property of *isLoading* remains as *true*, resulting in rendering the loader. Once succeeded, the compoents are updated with the initial random records. If a user click the button, it'll *commit* `updateVisData()`, resulting in compoent updates.

```html
<script>
import DataTable from './components/DataTable.vue'
import Highchart from './components/HighChart.vue'
import Plotly from './components/Plotly.vue'

export default {
  components: {
    appDataTable: DataTable,
    appHighchart: Highchart,
    appPlotly: Plotly
  },
  computed: {
    visData() {
      return this.$store.getters['visData']
    },
    isLoading() {
      return this.$store.getters['isLoading']
    }
  },
  methods: {
    update() {
      this.$store.commit('updateVisData')
    }
  },
  created () {
    this.$store.dispatch('getRawData')
  }
}
</script>

<style scoped>
.centered {
  position: fixed; /* or absolute */
  top: 50%;
  left: 50%;
}
</style>
```

The screen shot of the app is shown below.

![](vue-native.png#center)
