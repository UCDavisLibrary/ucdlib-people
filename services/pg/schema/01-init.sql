-- Trigger to update updated_at column on update
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    -- Only set updated_at if it wasn't explicitly set in the UPDATE
    IF NEW.updated_at IS NULL OR NEW.updated_at = OLD.updated_at THEN
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

create or replace function try_cast_uuid(p_in text)
   returns UUID
as
$$
begin
  begin
    return $1::UUID;
  exception
    when others then
       return '00000000-0000-0000-0000-000000000000'::UUID;
  end;
end;
$$
language plpgsql;

CREATE TABLE IF NOT EXISTS cache (
    id SERIAL PRIMARY KEY,
    type VARCHAR(100),
    query TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::JSONB,
    created timestamp DEFAULT NOW()
);
COMMENT ON TABLE cache IS 'Cache table for storing http requests and other data';

CREATE TABLE IF NOT EXISTS app_user (
    app_user_id VARCHAR(200) PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    email VARCHAR(200) NOT NULL,
    last_login timestamp,
    app_user_settings JSONB NOT NULL DEFAULT '{}'::JSONB,
    created timestamp DEFAULT NOW()
);
COMMENT ON TABLE app_user IS 'Table for storing user information. Set when a user logs in';