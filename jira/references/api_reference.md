# Jira REST API v2 Reference

## Base Configuration

```
BASE_URL: https://jira.tc-gaming.co/jira
API_PATH: /rest/api/2
AUTH_HEADER: "Authorization: Bearer $JIRA_PAT"
```

All requests use: `curl -sS -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json"`

Abbreviation used below: `JIRA="https://jira.tc-gaming.co/jira/rest/api/2"`

## Issue Operations

### Get Issue
```bash
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$JIRA/issue/{issueKey}"
```
Optional: `?fields=summary,status,assignee,priority&expand=changelog`

### Create Issue
```bash
curl -sS -X POST -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json" \
  "$JIRA/issue" -d '{
  "fields": {
    "project": {"key": "PROJECT_KEY"},
    "summary": "Issue title",
    "description": "Issue description",
    "issuetype": {"name": "Bug|Story|Task|Sub-task"},
    "priority": {"name": "High|Medium|Low"},
    "assignee": {"name": "username"},
    "labels": ["label1"],
    "components": [{"name": "component1"}]
  }
}'
```

### Update Issue
```bash
curl -sS -X PUT -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json" \
  "$JIRA/issue/{issueKey}" -d '{
  "fields": {
    "summary": "Updated title",
    "description": "Updated description",
    "assignee": {"name": "username"},
    "priority": {"name": "High"}
  }
}'
```

### Delete Issue
```bash
curl -sS -X DELETE -H "Authorization: Bearer $JIRA_PAT" "$JIRA/issue/{issueKey}"
```

## Comments

### Get Comments
```bash
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$JIRA/issue/{issueKey}/comment"
```

### Add Comment
```bash
curl -sS -X POST -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json" \
  "$JIRA/issue/{issueKey}/comment" -d '{"body": "Comment text"}'
```

## Transitions (Status Changes)

### Get Available Transitions
```bash
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$JIRA/issue/{issueKey}/transitions"
```

### Execute Transition
```bash
curl -sS -X POST -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json" \
  "$JIRA/issue/{issueKey}/transitions" -d '{
  "transition": {"id": "TRANSITION_ID"},
  "fields": {"resolution": {"name": "Done"}}
}'
```
Always GET transitions first to find the correct transition ID.

## Search (JQL)

```bash
curl -sS -H "Authorization: Bearer $JIRA_PAT" -G "$JIRA/search" \
  --data-urlencode "jql=project = KEY AND status = 'In Progress' ORDER BY updated DESC" \
  --data-urlencode "fields=summary,status,assignee,priority,updated" \
  --data-urlencode "maxResults=50" \
  --data-urlencode "startAt=0"
```

Common JQL patterns:
- `assignee = currentUser()` — my issues
- `assignee = "username"` — specific user
- `project = KEY AND sprint in openSprints()` — current sprint
- `project = KEY AND fixVersion = "1.0"` — by version
- `status changed to "Done" after -7d` — recently closed
- `text ~ "keyword"` — full text search
- `labels in ("label1", "label2")` — by labels

## Assign Issue

```bash
curl -sS -X PUT -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json" \
  "$JIRA/issue/{issueKey}/assignee" -d '{"name": "username"}'
```

## Worklog

```bash
curl -sS -X POST -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json" \
  "$JIRA/issue/{issueKey}/worklog" -d '{"timeSpent": "2h 30m", "comment": "Work description"}'
```

## Project

```bash
# List all projects
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$JIRA/project"

# Get project detail
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$JIRA/project/{projectKey}"
```

## Attachments

```bash
curl -sS -X POST -H "Authorization: Bearer $JIRA_PAT" -H "X-Atlassian-Token: no-check" \
  -F "file=@/path/to/file.png" "$JIRA/issue/{issueKey}/attachments"
```
Note: Do NOT include Content-Type header for multipart upload.

## Issue Links

```bash
curl -sS -X POST -H "Authorization: Bearer $JIRA_PAT" -H "Content-Type: application/json" \
  "$JIRA/issueLink" -d '{
  "type": {"name": "Blocks"},
  "inwardIssue": {"key": "TCG-123"},
  "outwardIssue": {"key": "TCG-456"}
}'
```
Common link types: Blocks, Cloners, Duplicate, Relates

## Agile API (Sprint/Board)

Base path: `/rest/agile/1.0` → `AGILE="https://jira.tc-gaming.co/jira/rest/agile/1.0"`

```bash
# Get board
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$AGILE/board?projectKeyOrId=KEY"

# Active sprint
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$AGILE/board/{boardId}/sprint?state=active"

# Sprint issues
curl -sS -H "Authorization: Bearer $JIRA_PAT" "$AGILE/sprint/{sprintId}/issue"
```

## jq Parsing Tips

- `.fields.summary` — title
- `.fields.status.name` — status
- `.fields.assignee.displayName` — assignee
- `.fields.priority.name` — priority
- `.issues[] | {key, summary: .fields.summary, status: .fields.status.name}` — search summary

## Error Codes

- **401**: Token invalid/expired — check `$JIRA_PAT`
- **403**: No permission
- **404**: Issue/project not found
- **400**: Malformed JSON payload
