import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Snapshot, Balance, sample } from '../core/Core';

export class HistoryStore {
  private database: relationalStore.RdbStore | undefined = undefined;
  private opening: Promise<relationalStore.RdbStore> | undefined = undefined;
  private context: common.Context;
  private databaseName: string;
  constructor(context: common.Context, databaseName: string = 'balance-history.db') {
    this.context = context;
    this.databaseName = databaseName;
  }

  private async db(): Promise<relationalStore.RdbStore> {
    if (this.database) return this.database;
    if (!this.opening) this.opening = this.open().finally(() => { this.opening = undefined; });
    return this.opening;
  }

  private async open(): Promise<relationalStore.RdbStore> {
    const database: relationalStore.RdbStore = await relationalStore.getRdbStore(this.context,
      { name: this.databaseName, securityLevel: relationalStore.SecurityLevel.S2 });
    await database.executeSql('CREATE TABLE IF NOT EXISTS snapshots (account_id TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, at INTEGER NOT NULL, revision INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(account_id,revision,at))');
    this.database = database;
    return database;
  }

  private point(rows: relationalStore.ResultSet): Snapshot {
    const p: Snapshot = new Snapshot();
    p.accountId = rows.getString(rows.getColumnIndex('account_id'));
    p.value = rows.getDouble(rows.getColumnIndex('amount'));
    p.currency = rows.getString(rows.getColumnIndex('currency'));
    p.timestamp = rows.getLong(rows.getColumnIndex('at'));
    p.revision = rows.getLong(rows.getColumnIndex('revision'));
    return p;
  }

  async record(balance: Balance): Promise<void> {
    const database: relationalStore.RdbStore = await this.db();
    const rows: relationalStore.ResultSet = await database.querySql(
      'SELECT * FROM snapshots WHERE account_id=? AND revision=? ORDER BY at DESC LIMIT 1', [balance.accountId, balance.revision]);
    let previous: Snapshot | undefined = undefined;
    try { if (rows.goToFirstRow()) previous = this.point(rows); } finally { rows.close(); }
    const point: Snapshot | undefined = sample(previous, balance);
    if (point) await database.executeSql('INSERT OR IGNORE INTO snapshots(account_id,amount,currency,at,revision) VALUES(?,?,?,?,?)',
      [point.accountId, point.value, point.currency, point.timestamp, point.revision]);
    await database.executeSql('DELETE FROM snapshots WHERE at < ?', [Date.now() - 180 * 86400000]);
  }

  async all(): Promise<Snapshot[]> {
    const rows: relationalStore.ResultSet = await (await this.db()).querySql('SELECT * FROM snapshots ORDER BY at');
    const points: Snapshot[] = [];
    try { while (rows.goToNextRow()) points.push(this.point(rows)); } finally { rows.close(); }
    return points;
  }

  async remove(id: string): Promise<void> {
    await (await this.db()).executeSql('DELETE FROM snapshots WHERE account_id=?', [id]);
  }
}
