

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- ENUM TYPES
-- ---------------------------------------------------------------------------

CREATE TYPE membership_role AS ENUM ('OWNER', 'ADMIN', 'MEMBER');
CREATE TYPE task_status AS ENUM ('TODO', 'IN_PROGRESS', 'DONE');
CREATE TYPE task_priority AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'URGENT');

CREATE TYPE activity_action AS ENUM (
    'WORKSPACE_CREATED',
    'PROJECT_CREATED',
    'PROJECT_UPDATED',
    'TASK_CREATED',
    'TASK_UPDATED',
    'TASK_ASSIGNED',
    'TASK_STATUS_CHANGED',
    'TASK_COMMENTED',
    'MEMBER_JOINED',
    'MEMBER_ROLE_CHANGED'
);

CREATE TYPE notification_type AS ENUM (
    'TASK_ASSIGNED',
    'TASK_STATUS_CHANGED',
    'TASK_COMMENTED',
    'TASK_DUE_SOON',
    'WORKSPACE_INVITATION'
);

CREATE TYPE invitation_status AS ENUM ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED');

-- ---------------------------------------------------------------------------
-- USERS
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(320) NOT NULL,
    password_hash TEXT NOT NULL,
    name VARCHAR(120) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT users_email_not_blank CHECK (length(trim(email)) > 0),
    CONSTRAINT users_password_hash_not_blank CHECK (length(trim(password_hash)) > 0),
    CONSTRAINT users_name_not_blank CHECK (length(trim(name)) > 0)
);

-- Case-insensitive uniqueness. Store normalized email from the application too.
CREATE UNIQUE INDEX users_email_lower_unique ON users (LOWER(email));

-- ---------------------------------------------------------------------------
-- WORKSPACES AND MEMBERSHIPS
-- ---------------------------------------------------------------------------

CREATE TABLE workspaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(160) NOT NULL,
    owner_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT workspaces_name_not_blank CHECK (length(trim(name)) > 0),
    CONSTRAINT workspaces_owner_fk
        FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE TABLE memberships (
    user_id UUID NOT NULL,
    workspace_id UUID NOT NULL,
    role membership_role NOT NULL DEFAULT 'MEMBER',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT memberships_pk PRIMARY KEY (user_id, workspace_id),
    -- Supports composite foreign keys that also validate the role.
    CONSTRAINT memberships_user_workspace_role_unique UNIQUE (user_id, workspace_id, role),
    CONSTRAINT memberships_user_fk
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT memberships_workspace_fk
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE INDEX workspaces_owner_id_idx ON workspaces(owner_id);
CREATE INDEX memberships_workspace_id_idx ON memberships(workspace_id);
CREATE INDEX memberships_workspace_role_idx ON memberships(workspace_id, role);

-- ---------------------------------------------------------------------------
-- PROJECTS AND TASKS
-- ---------------------------------------------------------------------------

CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    name VARCHAR(160) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Needed to let tasks reference both project and workspace consistently.
    CONSTRAINT projects_id_workspace_unique UNIQUE (id, workspace_id),
    CONSTRAINT projects_name_not_blank CHECK (length(trim(name)) > 0),
    CONSTRAINT projects_workspace_fk
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL,
    workspace_id UUID NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    status task_status NOT NULL DEFAULT 'TODO',
    priority task_priority NOT NULL DEFAULT 'MEDIUM',
    assignee_id UUID,
    due_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT tasks_id_workspace_unique UNIQUE (id, workspace_id),
    CONSTRAINT tasks_title_not_blank CHECK (length(trim(title)) > 0),
    CONSTRAINT tasks_project_workspace_fk
        FOREIGN KEY (project_id, workspace_id)
        REFERENCES projects(id, workspace_id) ON DELETE CASCADE,
    -- If assigned, the assignee must be a member of this task's workspace.
    CONSTRAINT tasks_assignee_membership_fk
        FOREIGN KEY (assignee_id, workspace_id)
        REFERENCES memberships(user_id, workspace_id)
        ON DELETE SET NULL (assignee_id)
);

CREATE INDEX projects_workspace_created_at_idx
    ON projects(workspace_id, created_at DESC);

CREATE INDEX tasks_project_id_idx ON tasks(project_id);
CREATE INDEX tasks_workspace_id_idx ON tasks(workspace_id);
CREATE INDEX tasks_assignee_id_idx ON tasks(assignee_id);
CREATE INDEX tasks_status_idx ON tasks(status);
CREATE INDEX tasks_due_date_idx ON tasks(due_date) WHERE due_date IS NOT NULL;
CREATE INDEX tasks_project_status_idx ON tasks(project_id, status);
CREATE INDEX tasks_assignee_status_idx ON tasks(assignee_id, status);
CREATE INDEX tasks_workspace_status_created_idx
    ON tasks(workspace_id, status, created_at DESC);

-- ---------------------------------------------------------------------------
-- COMMENTS
-- ---------------------------------------------------------------------------

CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL,
    workspace_id UUID NOT NULL,
    author_id UUID NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT comments_content_not_blank CHECK (length(trim(content)) > 0),
    CONSTRAINT comments_task_workspace_fk
        FOREIGN KEY (task_id, workspace_id)
        REFERENCES tasks(id, workspace_id) ON DELETE CASCADE,
    CONSTRAINT comments_author_membership_fk
        FOREIGN KEY (author_id, workspace_id)
        REFERENCES memberships(user_id, workspace_id)
        ON DELETE RESTRICT
);

CREATE INDEX comments_task_created_at_idx
    ON comments(task_id, created_at DESC);
CREATE INDEX comments_workspace_id_idx ON comments(workspace_id);

-- ---------------------------------------------------------------------------
-- ACTIVITY LOG
-- ---------------------------------------------------------------------------

CREATE TABLE activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    actor_id UUID,
    task_id UUID,
    action activity_action NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT activities_metadata_object
        CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT activities_workspace_fk
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT activities_actor_membership_fk
        FOREIGN KEY (actor_id, workspace_id)
        REFERENCES memberships(user_id, workspace_id)
        ON DELETE SET NULL (actor_id),
    CONSTRAINT activities_task_workspace_fk
        FOREIGN KEY (task_id, workspace_id)
        REFERENCES tasks(id, workspace_id) ON DELETE SET NULL (task_id)
);

CREATE INDEX activities_workspace_created_at_idx
    ON activities(workspace_id, created_at DESC);
CREATE INDEX activities_task_id_idx ON activities(task_id) WHERE task_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL,
    type notification_type NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT notifications_payload_object
        CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT notifications_recipient_fk
        FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX notifications_recipient_read_created_idx
    ON notifications(recipient_id, read_at, created_at DESC);

-- ---------------------------------------------------------------------------
-- WORKSPACE INVITATIONS
-- Invitations are optional in the MVP. Store only a hash of the secret token.
-- ---------------------------------------------------------------------------

CREATE TABLE workspace_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    invited_email VARCHAR(320) NOT NULL,
    role membership_role NOT NULL DEFAULT 'MEMBER',
    token_hash TEXT NOT NULL UNIQUE,
    invited_by UUID NOT NULL,
    status invitation_status NOT NULL DEFAULT 'PENDING',
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT workspace_invitations_email_not_blank
        CHECK (length(trim(invited_email)) > 0),
    CONSTRAINT workspace_invitations_token_not_blank
        CHECK (length(trim(token_hash)) > 0),
    CONSTRAINT workspace_invitations_expiry_after_creation
        CHECK (expires_at > created_at),
    CONSTRAINT workspace_invitations_no_owner_invite
        CHECK (role <> 'OWNER'),
    CONSTRAINT workspace_invitations_workspace_fk
        FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT workspace_invitations_inviter_fk
        FOREIGN KEY (invited_by) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE INDEX workspace_invitations_workspace_status_idx
    ON workspace_invitations(workspace_id, status, created_at DESC);
CREATE INDEX workspace_invitations_email_lower_idx
    ON workspace_invitations(LOWER(invited_email));

-- ---------------------------------------------------------------------------
-- REFRESH TOKENS
-- Store a hash of the refresh token, never the raw token.
-- ---------------------------------------------------------------------------

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT refresh_tokens_token_hash_not_blank
        CHECK (length(trim(token_hash)) > 0),
    CONSTRAINT refresh_tokens_expiry_after_creation
        CHECK (expires_at > created_at),
    CONSTRAINT refresh_tokens_user_fk
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX refresh_tokens_user_id_idx ON refresh_tokens(user_id);
CREATE INDEX refresh_tokens_active_expiry_idx
    ON refresh_tokens(expires_at) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- updated_at TRIGGER
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER workspaces_set_updated_at
    BEFORE UPDATE ON workspaces
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER memberships_set_updated_at
    BEFORE UPDATE ON memberships
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER projects_set_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER tasks_set_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER comments_set_updated_at
    BEFORE UPDATE ON comments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER workspace_invitations_set_updated_at
    BEFORE UPDATE ON workspace_invitations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- IMPORTANT APPLICATION TRANSACTION RULES
--
-- 1. Creating a workspace:
--    In one transaction, INSERT workspaces, then INSERT memberships with role
--    OWNER for that same user/workspace. Commit only if both inserts succeed.
--
-- 2. Owner changes:
--    Implement ownership transfer as a dedicated transaction. Update the
--    workspace owner and membership roles together; never allow a normal
--    member-role endpoint to demote/remove the current owner.
--
-- 3. Membership deletion/role change:
--    Before removing a member or changing their role, verify they are not the
--    current workspace owner. If they are, transfer ownership first.
--
-- 4. Task assignment:
--    The composite FK guarantees assignee_id is a member of workspace_id.
--    The backend must still authorize the acting user and verify the selected
--    assignee is allowed by the product's business rules.
--
-- 5. Comments and activities:
--    The composite FKs guarantee the author/actor (when non-null) belongs to
--    the specified workspace, and the task belongs to that same workspace.
--    Backend must still check whether the actor may perform the action.
--
-- 6. All user input must be passed as parameterized SQL ($1, $2, ...).
--    Never concatenate untrusted input into SQL strings.
--
-- 7. Normalize email in the application (trim + lowercase) on register/login.
--    Invitation email comparisons should also be case-insensitive.
--
-- 8. This file is intended for a fresh database. For later schema changes,
--    create versioned SQL migrations rather than rerunning this file.
-- ---------------------------------------------------------------------------

COMMIT;
