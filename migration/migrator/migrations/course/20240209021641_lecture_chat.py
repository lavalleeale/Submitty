"""Migration for a given Submitty course database."""

import json
from pathlib import Path

def up(config, database, semester, course):
    """
    Run up migration.
    :param config: Object holding configuration details about Submitty
    :type config: migrator.config.Config
    :param database: Object for interacting with given database for environment
    :type database: migrator.db.Database
    :param semester: Semester of the course being migrated
    :type semester: str
    :param course: Code of course being migrated
    :type course: str
    """

    database.execute(
    """
        CREATE TABLE IF NOT EXISTS chatrooms (
            id SERIAL PRIMARY KEY,
            host_id character varying NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
            host_name character varying,
            title text NOT NULL,
            description text,
            is_active BOOLEAN DEFAULT false NOT NULL,
            allow_anon BOOLEAN DEFAULT true NOT NULL
        );

        CREATE TABLE IF NOT EXISTS chatroom_messages (
            id SERIAL PRIMARY KEY,
            chatroom_id integer NOT NULL REFERENCES chatrooms(id) ON DELETE CASCADE,
            user_id character varying NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
            display_name character varying,
            role character varying,
            content text NOT NULL,
            timestamp timestamp(0) with time zone NOT NULL
        );
    """
    )

def down(config, database, semester, course):
    """
    Run down migration (rollback).
    :param config: Object holding configuration details about Submitty
    :type config: migrator.config.Config
    :param database: Object for interacting with given database for environment
    :type database: migrator.db.Database
    :param semester: Semester of the course being migrated
    :type semester: str
    :param course: Code of course being migrated
    :type course: str
    """
    database.execute("DROP TABLE IF EXISTS chatrooms cascade")
    database.execute("DROP TABLE IF EXISTS chatroom_messages")

    pass