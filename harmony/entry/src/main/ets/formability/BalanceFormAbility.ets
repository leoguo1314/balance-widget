import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Account, CardData, cardData } from '../core/Core';
import { Repository, FormInstance } from '../platform/Repository';
import { BalanceService } from '../platform/BalanceService';

class FormEvent { operation: string = ''; params: Record<string, string> = {}; }

export default class BalanceFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    try {
      const repository: Repository = Repository.open(this.context);
      const id: string = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] || '');
      const cached: CardData = cardData(repository.state.accounts, repository.state.balances, repository.state.settings.usdCny, 0);
      if (id) repository.setForm(id, 0).then(() => this.refresh(id)).catch(() => {});
      return formBindingData.createFormBindingData(cached);
    } catch (_) { return formBindingData.createFormBindingData(new CardData()); }
  }

  onUpdateForm(formId: string): void { this.refresh(formId).catch(() => {}); }

  onFormEvent(formId: string, message: string): void {
    try {
      const event: FormEvent = JSON.parse(message) as FormEvent;
      const operation: string = event.operation || event.params?.['operation'];
      if (operation !== 'next') return;
      const repository: Repository = Repository.open(this.context);
      const form: FormInstance | undefined = repository.state.forms.find((item: FormInstance) => item.id === formId);
      const page: number = (form?.page || 0) + 1;
      // 翻页只读本机缓存，不查询平台。
      repository.setForm(formId, page).then(() => formProvider.updateForm(formId,
        formBindingData.createFormBindingData(cardData(repository.state.accounts, repository.state.balances,
          repository.state.settings.usdCny, page)))).catch(() => {});
    } catch (_) { /* 无效消息不执行任何账户操作。 */ }
  }

  onRemoveForm(formId: string): void {
    try { Repository.open(this.context).removeForm(formId).catch(() => {}); } catch (_) {}
  }

  onAcquireFormState(_: Want): formInfo.FormState { return formInfo.FormState.READY; }

  private async refresh(id: string): Promise<void> {
    const repository: Repository = Repository.open(this.context);
    const form: FormInstance | undefined = repository.state.forms.find((item: FormInstance) => item.id === id);
    const active: Account[] = repository.state.accounts.filter((a: Account) => a.enabled);
    const pages: number = Math.max(1, Math.ceil(active.length / 4));
    const page: number = ((form?.page || 0) % pages + pages) % pages;
    // FormExtensionAbility 不常驻；每次仅并行查询当前卡片的最多四项。
    const ids: string[] = active.slice(page * 4, page * 4 + 4).map((a: Account) => a.id);
    await new BalanceService(repository).refresh(ids);
  }
}
