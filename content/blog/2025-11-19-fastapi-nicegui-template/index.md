---
title: Guide to Building Integrated Web Applications with FastAPI and NiceGUI
date: 2025-11-19
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
categories: 
  - Development
tags:
  - FastAPI
  - NiceGUI
  - Python
  - Full-Stack
  - Web Development
  - Software Architecture
  - UI Development
  - Internal Tools
  - Docker
  - Pydantic
  - PostgreSQL
  - SQLModel
authors:
  - JaehyeonKim
images: []
description: 
---

The standard architecture for modern web applications involves a decoupled frontend, typically built with a JavaScript framework, and a backend API. This pattern is powerful but introduces complexity in managing two separate codebases, development environments, and the API contract between them.

This article explores an alternative approach: an integrated architecture where the backend API and the frontend UI are served from a single, cohesive Python application. 

<!--more-->

We will provide a technical analysis of this architecture's implementation by integrating FastAPI and NiceGUI, referencing the complete project template available at [jaehyeon-kim/nicegui-fastapi-template](https://github.com/jaehyeon-kim/nicegui-fastapi-template).

---

## 💡 Version 2.0: Unified Application Architecture

The initial version was designed with a distinct separation between a FastAPI backend and a NiceGUI frontend, which communicated over HTTP. This new version consolidates the application, leveraging the fact that NiceGUI is built on top of FastAPI. The result is a more tightly integrated structure that allows the UI and API logic to coexist in the same process.

### Key Architectural Changes

- **Single FastAPI Instance:** The separate FastAPI server process has been removed. The application now operates on the single FastAPI instance provided by `nicegui.app`.
- **Direct Function Calls:** UI event handlers no longer make HTTP requests (`httpx`) to the backend. They now import and call the necessary Python functions from the repository layer directly, removing the network layer for UI-to-backend communication.
- **Preserved API Endpoints:** The original API, intended for external clients, is maintained. It is mounted using FastAPI's `APIRouter` onto the main NiceGUI application, ensuring that JSON endpoints remain available.
- **Consolidated Codebase:** The `frontend` and `backend` directories have been merged into a single application package (e.g., `app` or `src`). A `run.py` script at the project root now serves as the single entry point.
- **Shared Logic:** Business logic, such as permission checks and database operations, has been centralized in the repository layer, where it is called by both the UI event handlers and the API endpoints.

This updated architecture provides a more direct and cohesive way to build full-stack applications where the UI and backend logic are tightly coupled.

### Project Structure

The application is structured with a single entry point, **`app.py`**, at the project root, and a main source package, **`src/`**, which contains all the application's logic. This design provides a clear separation between the runnable script and the installable source code.

*   **`app.py`**: This script is the single entry point for the application. It is responsible for creating the main NiceGUI `app` instance, including all the API routers from `src/backend/`, importing the UI pages from `src/frontend/` to register their routes, and starting the web server.

*   **`src/`**: This directory is the main Python package for the application. It contains all the core logic, API definitions, and UI code, organized into the following modules:
    *   **`backend/`**: Contains the code for the data-only API, intended for external clients.
        *   `endpoints/`: Each file defines a set of related API routes (e.g., for items, users, login) using FastAPI's `APIRouter`.
        *   `deps.py`: Manages FastAPI's dependency injection system for the API, such as providing database sessions or the current authenticated user.
    *   **`core/`**: Holds application-wide configuration (`config.py`) and security-related functions like password hashing and token creation (`security.py`).
    *   **`db/`**: Manages all database interactions, including engine creation, session management (`session.py`), and initial database setup (`init_db.py`).
    *   **`frontend/`**: Contains all the NiceGUI code for the user interface.
        *   `components/`: Holds reusable UI elements and utilities, such as `header.py`, `footer.py`, `notifications.py`, and authentication helpers in `auth_utils.py`.
        *   `layouts/`: Defines the overall page structure, like the main dashboard frame, ensuring a consistent look and feel.
        *   `pages/`: Each file represents a specific UI view, such as the login screen (`login.py`) or the item management page (`items.py`), using the `@ui.page` decorator.
        *   `state.py`: A module for managing UI-specific state, like the user's authentication token.
    *   **`models/`**: Contains the SQLModel (and Pydantic) schemas that define database tables and data structures used across the entire application.
    *   **`repositories/`**: This is the core business logic and data access layer. It abstracts all database queries and contains functions for data manipulation. In this unified architecture, its functions are now called directly by **both** the API endpoints in `src/backend/` and the UI event handlers in `src/frontend/`.

---

## FastAPI Backend

FastAPI provides a robust foundation for the backend due to several key technical features:

*   **ASGI Foundation:** Built on the Asynchronous Server Gateway Interface (ASGI), FastAPI natively supports asynchronous operations. This allows it to handle high-concurrency, I/O-bound tasks, such as network requests and database queries, efficiently without blocking the server.
*   **Schema Generation and Data Validation:** FastAPI uses Pydantic models for strict, type-hint-based data validation and serialization. These models automatically generate OpenAPI schemas, which power the interactive API documentation (via Swagger UI and ReDoc) and ensure that the API contract is clearly defined and enforced.
*   **Dependency Injection System:** Its dependency injection system is a core feature that enhances modularity and testability. It allows for the management of dependencies like database sessions and authentication credentials, ensuring that resources are correctly provisioned and cleaned up for each request.

## NiceGUI Frontend

NiceGUI serves as the frontend component, allowing for UI development entirely within Python.

*   **Pythonic Abstraction of Web Technologies:** NiceGUI functions as an abstraction layer that generates the necessary HTML, CSS, and JavaScript from Python objects and methods. This allows developers to define complex user interfaces without writing client-side code directly.
*   **Server-Side Event Handling:** The framework employs an event-driven model where UI components are bound to Python callback functions. User interactions (e.g., button clicks, form submissions) trigger these functions, which execute on the server. This creates a direct and clear link between a UI event and its corresponding backend logic.
*   **Server-Maintained State:** Unlike JavaScript frontend frameworks that manage state on the client, NiceGUI maintains the UI state within the server's Python process. This simplifies application logic, as there is no need for complex state synchronization mechanisms between client and server.

## Architectural Advantages and Framework Comparisons

### The Integrated Server Approach

In this architecture, the NiceGUI application is mounted directly onto the FastAPI instance. This is typically done with a single function call, creating a unified application that serves both API endpoints and the user interface from one process.

The primary benefit is the ability to use shared data models (e.g., SQLModel or Pydantic) across the entire stack. A model defined once can be used to structure a database table, validate an API request payload, and define the data contract for the UI. This ensures end-to-end data consistency and reduces code duplication, as all parts of the application are built around the same data structures.

### NiceGUI vs. JavaScript Frameworks (e.g., React, Vue)

*   **Bridging the Expertise Gap:** Acquiring deep expertise in both backend Python and a modern JavaScript frontend framework is a significant undertaking. NiceGUI directly addresses this by enabling Python developers to build sophisticated user interfaces without leaving the Python ecosystem. This allows them to leverage their existing skills rather than learning a new language and its complex toolchain.
*   **Leveraging Mature Frontend Technologies:** NiceGUI is not a proprietary UI system built from scratch. It is built on top of the robust and widely-used Vue and Quasar frameworks. This provides the best of both worlds: developers interact with a simple Pythonic API while benefiting from the power, performance, and rich component library of a mature frontend technology.
*   **Trade-offs:** The server-side rendering approach is highly efficient for internal tools and data-heavy applications. However, because every interaction requires a round-trip to the server, it may introduce latency on highly interactive UIs compared to a client-side Single Page Application (SPA), which can handle many state changes without network requests.

### NiceGUI vs. Streamlit

*   **Control and Layout:** NiceGUI provides more granular control over UI component placement and application layout, using rows, columns, and grids. This makes it well-suited for building applications with a structured, traditional design. Streamlit is more opinionated, favoring a simple, top-to-bottom script execution model that is excellent for linear data narratives but offers less layout flexibility.
*   **Event Handling and Execution Model:** Both frameworks use callbacks, but their underlying execution models differ significantly. NiceGUI uses a persistent component model where an event, such as a button click, executes a specific callback function (`on_click=handle_click`). This function is the *only* code that runs and is responsible for explicitly updating any UI elements. This aligns closely with traditional GUI programming paradigms. In contrast, Streamlit uses a script re-run model. While it also has an `on_click` callback, this function typically modifies a session state object. After the callback completes, Streamlit **re-runs the entire application script from top to bottom**. The UI is then re-rendered based on the new values in the session state. This model simplifies the creation of linear, data-centric apps but can be less direct and potentially less performant for managing complex, multi-state interfaces compared to NiceGUI's explicit event-driven approach.
*   **Integration:** NiceGUI is designed to be a component that can be integrated with standard web frameworks like FastAPI. Streamlit is generally used as a self-contained application server and is less straightforward to embed within another ASGI application.

## Implementation Overview

To provide a concrete example of this architecture, the reference repository at [jaehyeon-kim/nicegui-fastapi-template](https://github.com/jaehyeon-kim/nicegui-fastapi-template) contains a fully functional application. Let's examine its structure and key components.

### Project Structure

The project is organized into two main directories, ensuring a clear separation of concerns between the backend logic and the user interface:

*   **`backend/`**: This directory contains all the FastAPI source code. It is further subdivided into modules for handling specific responsibilities:
    *   `api/`: Defines the API endpoints for resources like users and items.
    *   `db/`: Manages the database session and engine configuration.
    *   `models/`: Contains the SQLModel (and Pydantic) data schemas that define our database tables and API data structures.
    *   `repositories/`: Implements the data access layer, abstracting the database queries from the API endpoints.
*   **`frontend/`**: This directory holds all the NiceGUI code for the user interface, organized by function into the following subdirectories and modules:
    *   **`components/`**: Contains reusable UI elements and helper functions. This includes visual components like `header.py` and `footer.py`, as well as utility modules like `notifications.py` for displaying messages to the user and `form_helpers.py` for handling common form logic.
    *   **`layouts/`**: Defines the overall structure of the application's pages. The `default.py` file, for instance, assembles the header, drawer, and footer to ensure a consistent look and feel across different views.
    *   **`pages/`**: Each file in this directory represents a specific page or view within the application, such as the login screen (`login.py`), the item management page (`items.py`), and the user creation form (`create_user.py`).
    *   **`state.py`**: A dedicated module for managing the application's client-side state, such as user authentication status. This allows different parts of the UI to react consistently to changes in state.
*   **`backend/main.py`**: This file serves as the central integration point. It initializes the FastAPI application, includes the API routers from the `backend/api/` directory, and finally, mounts the entire NiceGUI frontend. This is where the two parts of the application become one.

### Application Demo

The repository provides a complete user and item management application that showcases role-based access control. The functionality is divided between two user roles:

*   **Standard User:** After logging in, a standard user has full CRUD (Create, Read, Update, Delete) permissions over their own items. They can add new items, view their list, and edit or delete them as needed.

*   **Superuser:** A superuser has elevated privileges. In addition to managing their own items, they can also create new user accounts. Crucially, they have a global view of the system and can manage the items belonging to any user, making this role suitable for administrative purposes.

![](featured.gif#center)

The demo showcases these distinct workflows, illustrating how the NiceGUI frontend dynamically adapts to the user's permissions, which are enforced by the FastAPI backend.

### Automatic API Documentation

One of the most powerful features of FastAPI is its ability to automatically generate interactive API documentation from the Pydantic models and endpoint definitions. The application provides two documentation interfaces out-of-the-box:

*   **Swagger UI (`/docs`)**: A feature-rich, interactive interface that allows developers to not only view the API endpoints but also test them directly from the browser by sending live requests.

![](docs.png#center)

*   **ReDoc (`/redoc`)**: A clean, read-only documentation page that presents the API in a more traditional, hierarchical format. It is excellent for quickly referencing endpoints and their schemas.

![](redoc.png#center)

These auto-generated documents are invaluable for development, testing, and collaboration, and they are created without any extra effort, thanks to FastAPI's adherence to the OpenAPI standard.

## Summary and Use Cases

The integration of FastAPI and NiceGUI provides a robust architecture for building web applications entirely in Python. It streamlines development by creating a unified environment, simplifies deployment to a single process, and ensures strong data consistency through the use of shared models.

This architecture is exceptionally well-suited for:

*   **Internal Tools and Administrative Dashboards:** Where rapid development and ease of maintenance are critical.
*   **Rapid Prototyping and MVPs:** To quickly build and validate a functional application.
*   **Machine Learning and Data Science Demos:** To create interactive interfaces for models without requiring frontend expertise.

While it may not be the optimal choice for every project, particularly those requiring complex client-side interactivity, it offers a powerful and efficient alternative for a significant class of web applications. For a practical implementation, refer to the project code at [jaehyeon-kim/nicegui-fastapi-template](https://github.com/jaehyeon-kim/nicegui-fastapi-template).
