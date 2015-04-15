# tbcd

## Description

Tbcd(Task BroadCast Deamon) is a web system for broadcasting tasks to all
workers associated with a project.

## APIs

The requests to the APIs need be with a  POST method, and the body of request
and response should be json-encoded format.

### Project

URI: `/project`

#### Add a project or add workers to a project

##### Request
```json
{"mode":"add", "project":"dummy", "workers":["w1", "w2", "w3"]}
```
##### Response
```json
{"code":0}
```

#### Delete workers from a project or delete a project

**Note: when no `workers` argument supplied or `workers` argument is a empty
list, this API would delete the entile project.**

##### Request
```json
{"mode":"delete", "project":"dummy", "workers":["w1", "w2"]}
```

##### Response
```json
{"code":0}
```

#### Query workers in a project or query all projects

##### Request
```json
{"mode":"select", "project":"dummy"}
```
##### Response
```json
{"code":0, "workers":["w1", "w2"]}
```
When need get all projects, do not supply `project` argument.

##### Request
```json
{"mode":"select"}
```

##### Response
```json
{"code":0, "projects":["dummy1", "dummy2"]}
```

### Task

URI: `/task`

#### Submit a task

##### Request
`callback` argument is optional.
```json
{"mode":"add",
 "project":"dummy",
 "content":"balabala...",
 "callback":"http://domain/path/to/uri"}
```
##### Response
```json
{"code":0, "tid":"tid1"}
```

#### Query status of tasks

##### Request
```json
{"mode":"select", "tids":["tid1", "tid2"]}
```

##### Response
```json
{"code":0, "tasks":[{"tid":"tid1", "status":0}, {"tid":"tid2", "status":3}]}
```
When `status` was 0, all the workers completed the task.

### Subtask

URI: `/subtask`

#### Fetch subtasks

When no subtasks can be dispatched, tbcd would hanged the request to some
subtasks is ready or timeout. When timeout, HTTP code 204 would be returned.

##### Request
```json
{"mode":"fetch", "worker":"w1"}
```

##### Response
```json
{"code":0,
 "subtasks":[{"tid":"task1", "project":"dummy", "content":"balabala"},
             {"tid":"task2", "project":"dummy", "content":"balabala"}]}
```

#### Feedback result of subtasks

##### Request
```json
{"mode":"feedback",
 "worker":"w1",
 "subtasks":[{"tid":"task1", "result":"ok"},
             {"tid":"task2", "result":"failed"}]}
```

##### Response
```json
{"code":0}
```
### Callback

When all the workers completed the task, tbcd would call the HTTP API associated with the task in `callback` argument when submitted.

Request:
```json
{"tid":"task1",
 "results":[{"worker":"w1", "result":"ok"},
            {"worker":"w2", "result":"failed"}]}
```

### Failed Response

When someone of the APIs failed, the response would be like this:
```json
{"code":1, "reason":"balabala ..."}
```

## Authors

- Gu Feng <flygoast@126.com>
