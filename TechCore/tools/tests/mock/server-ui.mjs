// Имитация @minecraft/server-ui: ответы форм задаются очередью responses.
export const FormCancelationReason = { UserBusy: "UserBusy", UserClosed: "UserClosed" };

export const ui = { responses: [], shown: [] };

class BaseForm {
  constructor() {
    this.items = [];
    this._title = "";
    this._body = "";
  }
  title(t) {
    this._title = t;
    return this;
  }
  body(t) {
    this._body = t;
    return this;
  }
  label(t) {
    this.items.push({ type: "label", t });
    return this;
  }
  header(t) {
    this.items.push({ type: "header", t });
    return this;
  }
  divider() {
    this.items.push({ type: "divider" });
    return this;
  }
  async show() {
    ui.shown.push(this);
    const r = ui.responses.shift();
    if (r === undefined) return { canceled: true, cancelationReason: FormCancelationReason.UserClosed };
    return typeof r === "function" ? r(this) : r;
  }
}

export class ActionFormData extends BaseForm {
  button(text, icon) {
    this.items.push({ type: "button", text, icon });
    return this;
  }
  get buttons() {
    return this.items.filter((i) => i.type === "button");
  }
}

export class ModalFormData extends BaseForm {
  dropdown(label, options, o) {
    this.items.push({ type: "dropdown", label, options, o });
    return this;
  }
  toggle(label, o) {
    this.items.push({ type: "toggle", label, o });
    return this;
  }
  slider(label, a, b, o) {
    this.items.push({ type: "slider", label, a, b, o });
    return this;
  }
  textField(label, p, o) {
    this.items.push({ type: "text", label, p, o });
    return this;
  }
  submitButton(t) {
    this._submit = t;
    return this;
  }
}

export class MessageFormData extends BaseForm {}
