class DBMigrator
  def self.from_config(config, db_logger)
    VCAP::CloudController::Encryptor.db_encryption_key = config[:db_encryption_key]
    db = VCAP::CloudController::DB.connect(config[:db], db_logger)
    new(db)
  end

  def initialize(db)
    @db = db
  end

  def apply_migrations(opts = {})
    Sequel.extension :migration
    require "vcap/sequel_case_insensitive_string_monkeypatch"
    migrations_dir = File.expand_path("../../db", File.dirname(__FILE__))
    sequel_migrations = File.join(migrations_dir, "migrations")
    Sequel::Migrator.run(@db, sequel_migrations, opts)
  end

  def rollback(number_to_rollback)
    recent_migrations = @db[:schema_migrations].order(Sequel.desc(:filename)).limit(number_to_rollback + 1).all
    recent_migrations = recent_migrations.collect { |hash| hash[:filename].split("_", 2).first.to_i }
    apply_migrations(current: recent_migrations.first,
      target: recent_migrations.last)
  end
end
