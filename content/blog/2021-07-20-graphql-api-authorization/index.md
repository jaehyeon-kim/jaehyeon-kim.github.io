---
title: Adding Authorization to a Graphql API
date: 2021-07-20
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
  - Engineering
tags: 
  - Apollo
  - Authorization
  - GraphQL
  - Node.js
authors:
  - JaehyeonKim
images: []
cevo: 1
---

Authorization is the mechanism that controls who can do what on which resource in an application. Although it is a critical part of an application, there are limited resources available on how to build authorization into an app effectively. In this post, I'll be illustrating how to set up authorization in a GraphQL API using a custom [directive](https://www.apollographql.com/docs/apollo-server/schema/directives/) and [Oso](https://www.osohq.com/), an open-source authorization library. This tutorial covers the NodeJS variant of Oso, but it also supports Python and other languages.


## Requirements

There are a number of users and each of them belongs to one or more user groups. The groups are _guest_, _member_ and _admin_. Also, a user can be given escalated permission on one or more projects if he/she belongs to a certain project user group (e.g. _contributor_). 

![](relationship.png#center)

Depending on the membership, users have varying levels of permission on user, project and indicator resources. Specifically

User
* All users can be fetched if a user belongs to the _admin_ user group.

Project
* A project or all permitted projects can be queried if a user belongs to the _admin or member _user group or to the _contributor _user project group.
    * For a project record, the *contract_sum* field can be queried only if a user belongs to the _admin _user group or _contributor_ user project group.
* The project status can be updated if a user belongs to the _admin_ user group or _contributor_ user project group.

Indicator
* All permitted project indicators can be fetched if a user belongs to the _admin_ user group or _contributor_ user project group.

## Building Blocks

### Permission Specification on Directive

> A [directive ](https://www.apollographql.com/docs/apollo-server/schema/directives/) decorates part of a GraphQL schema or operation with additional configuration. Tools like Apollo Server (and Apollo Client) can read a GraphQL document's directives and perform custom logic as appropriate.

A directive can be useful to define permission. Below shows the type definitions used to meet the authorization requirements listed above. For example, the auth directive (_@auth_) is applied to the _project_ query where _admin_ and _member_ are required for the user groups and _contributor_ for the project user group. 


```js
// src/schema.js
const typeDefs = gql`
  directive @auth(
    userGroups: [UserGroup]
    projGroups: [ProjectGroup]
  ) on OBJECT | FIELD_DEFINITION

  ...

  type User {
    id: ID!
    name: String
    groups: [String]
  }

  type Project {
    id: ID!
    name: String
    status: String
    contract_sum: Int @auth(userGroups: [admin], projGroups: [contributor])
  }

  type Indicator {
    id: ID!
    project_id: Int
    risk: Int
    quality: Int
  }

  type Query {
    users: [User] @auth(userGroups: [admin])
    project(projectId: ID!): Project
      @auth(userGroups: [admin, member], projGroups: [contributor])
    projects: [Project]
      @auth(userGroups: [admin, member], projGroups: [contributor])
    indicators: [Indicator]
      @auth(userGroups: [admin], projGroups: [contributor])
  }

  type Mutation {
    updateProjectStatus(projectId: ID!, status: String!): Project
      @auth(userGroups: [admin], projGroups: [contributor])
  }
`;
```

### Policy Building Using Oso

> [Oso](https://www.osohq.com/) is a batteries-included library for building authorization in your application. Oso gives you a mental model and an authorization system – a set of APIs built on top of a declarative policy language called Polar, plus a debugger and REPL – to define who can do what in your application. You can express common concepts from “users can see their own data” and role-based access control, to others like multi-tenancy, organizations and teams, hierarchies and relationships.

An authorization policy is a set of logical rules for who is allowed to access what resources in an application. For example, the policy that describes the _get:project <span style="text-decoration:underline;">action</span>_ allows the _<span style="text-decoration:underline;">actor</span>_ _(user)_ to perform it on the _project <span style="text-decoration:underline;">resource</span>_ if he/she belongs to required user or project groups. The actor and resource can be either a custom class or one of the [built-in classes](https://docs.osohq.com/node/getting-started/policies.html) (Dictionary, List, String …). Note methods of a custom class can be used instead of built-in operations as well.


```js
# src/polars/policy.polar
allow(user: User, "list:users", _: String) if
  user.isRequiredUserGroup();

allow(user: User, "get:project", project: Dictionary) if
  user.isRequiredUserGroup()
  or
  user.isRequiredProjectGroup(project);

allow(user: User, "update:project", projectId: Integer) if
  user.isRequiredUserGroup()
  or
  projectId in user.filterAllowedProjectIds();

allow(user: User, "list:indicators", _: String) if
  user.isRequiredUserGroup()
  or
  user.filterAllowedProjectIds().length > 0;
```

### Policy Enforcement

#### Within Directive

The auth directive collects the user and project group configuration on an object or field definition. Then it updates the user object in the context and passes it to the resolver. In this way, policy enforcement for queries and mutations can be performed within the resolver, and it is more manageable while the number of queries and mutations increases. 

On the other hand, the policy of an object field (e.g. _contract_sum_) is enforced within the directive. It is because, once a query (e.g. _project_) or mutation is resolved, and its parent object is returned, the directive is executed for the field with different configuration values.


```js
// src/utils/directive.js
class AuthDirective extends SchemaDirectiveVisitor {
  ...

  ensureFieldsWrapped(objectType) {
    if (objectType._authFieldsWrapped) return;
    objectType._authFieldsWrapped = true;

    const fields = objectType.getFields();

    Object.keys(fields).forEach((fieldName) => {
      const field = fields[fieldName];
      const { resolve = defaultFieldResolver } = field;
      field.resolve = async function (...args) {
        const userGroups = field._userGroups || objectType._userGroups;
        const projGroups = field._projGroups || objectType._projGroups;
        if (!userGroups && !projGroups) {
          return resolve.apply(this, args);
        }

        const context = args[2];
        context.user.requires = { userGroups, projGroups };

        // check permission of fields that have a specific parent type
        if (args[3].parentType.name == "Project") {
          const user = User.clone(context.user);
          if (!(await context.oso.isAllowed(user, "get:project", args[0]))) {
            throw new ForbiddenError(
             JSON.stringify({ requires: user.requires, groups: user.groups })
            );
          }
        }

        return resolve.apply(this, args);
      };
    });
  }
}
```

#### Within Resolver

The Oso object is instantiated and stored in the context. Then a policy can be enforced with the corresponding _actor, action_ and _resource _triples. For list endpoints, different strategies can be employed. For example, the _projects_ query fetches all records, but returns only authorized records. On the other hand, the _indicators_ query is set to fetch only permitted records, which is more effective when dealing with sensitive data or a large amount of data. 


```js
// src/resolvers.js
const resolvers = {
  Query: {
    users: async (_, __, context) => {
      const user = User.clone(context.user);
      if (await context.oso.isAllowed(user, "list:users", "_")) {
        return await User.fetchUsers();
      } else {
        throw new ForbiddenError(
          JSON.stringify({ requires: user.requires, groups: user.groups })
        );
      }
    },
    project: async (_, args, context) => {
      const user = User.clone(context.user);
      const result = await Project.fetchProjects([args.projectId]);
      if (await context.oso.isAllowed(user, "get:project", result[0])) {
        return result[0];
      } else {
        throw new ForbiddenError(...);
      }
    },
    projects: async (_, __, context) => {
      const user = User.clone(context.user);
      const results = await Project.fetchProjects();
      const authorizedResults = [];
      for (const result of results) {
        if (await context.oso.isAllowed(user, "get:project", result)) {
          authorizedResults.push(result);
        }
      }
      return authorizedResults;
    },
    indicators: async (_, __, context) => {
      const user = User.clone(context.user);
      if (await context.oso.isAllowed(user, "list:indicators", "_")) {
        let projectIds;
        if (user.isRequiredUserGroup()) {
          projectIds = [];
        } else {
          projectIds = user.filterAllowedProjectIds();
          if (projectIds.length == 0) {
            throw new Error("fails to populate project ids");
          }
        }
        return await Project.fetchProjectIndicators(projectIds);
      } else {
        throw new ForbiddenError(...);
      }
    },
  },
  Mutation: {
    updateProjectStatus: async (_, args, context) => {
      const user = User.clone(context.user);
      if (
        await context.oso.isAllowed(
          User, "update:project", parseInt(args.projectId)
        )
      ) {
        return Project.updateProjectStatus(args.projectId, args.status);
      } else {
        throw new ForbiddenError(...);
      }
    },
  },
};
```
## Examples

The application source can be found in [this **GitHub repository**](https://github.com/jaehyeon-kim/graphql-authorization), and it can be started as follows.


```bash
docker-compose up
# if first time
docker-compose up --build
```

[Apollo Studio](https://www.apollographql.com/docs/studio/) can be used to query the example API. Note the server is running on port 5000, and it is expected to have one of the following values in the _name_ request header.

* `guest-user`
  * user group: guest
* `member-user`
  * user group: member	
  * user project group: contributor of project 1 and 3
* `admin-user`
  * user group: admin
* `contributor-user`
  * user group: guest
  * user project group: contributor of project 1, 3, 5, 8 and 12

The member user can query the project thanks to her user group membership. Also, as the user is a contributor of project 1 and 3, she has access to *contract_sum*.

![](example-01.png#center)


The query returns an error if a project that she is not a contributor is requested. The project query is resolved because of her user group membership while *contract_sum* turns to _null_.

![](example-02.png#center)


The contributor user can query all permitted projects without an error as shown below.

![](example-03.png#center)

## Conclusion

In this post, it is illustrated how to build authorization in a GraphQL API using a custom directive and an open source authorization library, Oso. A custom directive is effective to define permission on a schema, to pass configuration to the resolver and even to enforce policies directly. The Oso library helps build policies in a declarative way while expressing common concepts. Although it’s not covered in this post, the library supports building common authorization models such as role-based access control, multi-tenancy, hierarchies and relationships. It has a huge potential! I hope you find this post useful when building authorization in an application.
