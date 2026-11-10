use freya::prelude::*;
use freya::query::{MutationCapability, MutationStateData, UseMutation};
use oneclient_auth::MinecraftAccount;

use crate::components::{
    Avatar, Button, Icon, IconType, OverlayPopup, TextInput, use_microsoft_login,
};
use crate::hooks::{AddOfflineAccountKeys, try_default_account, use_add_offline_account,
    use_current_account};
use crate::i18n::t;
use crate::routes::Route;
use crate::theme::{colors, rounded, text_size};
use crate::ui::border_all_color;
use crate::view::onboarding::{
    onboarding_illustration, onboarding_nav, onboarding_page, step_heading,
};

#[derive(PartialEq)]
pub struct OnboardingAccount;

impl Component for OnboardingAccount {
    fn render(&self) -> impl IntoElement {
        let account_query = use_current_account();
        let msa = use_microsoft_login();
        let add_offline = use_add_offline_account();

        let mut username = use_state(String::new);
        let mut show_offline = use_state(|| false);
        let mut closing_offline = use_state(|| false);

        use_side_effect(move || {
            if !*closing_offline.read() {
                return;
            }
            match &*add_offline.read().state() {
                MutationStateData::Settled { res: Ok(_), .. } => {
                    closing_offline.set(false);
                    show_offline.set(false);
                    username.set(String::new());
                }
                MutationStateData::Settled { res: Err(_), .. } => {
                    closing_offline.set(false);
                }
                _ => {}
            }
        });

        let account = try_default_account(&account_query);
        let has_account = account.is_some();

        let offline_name = username.read().trim().to_string();
        let offline_uuid = (!offline_name.is_empty())
            .then(|| oneclient_auth::offline_uuid(&offline_name).to_string());
        let offline_error = mutation_err_text(&add_offline);

        let on_confirm_offline = move |_| {
            let name = username.peek().trim().to_string();
            if name.is_empty() {
                return;
            }
            add_offline.mutate(AddOfflineAccountKeys { username: name });
            closing_offline.set(true);
        };

        let content = rect()
            .vertical()
            .width(Size::fill())
            .spacing(24.)
            .child(step_heading(
                t("oneclient.onboarding.account.title"),
                t("oneclient.onboarding.account.subtitle"),
            ))
            .child(match &account {
                Some(account) => account_preview(account).into_element(),
                None => sign_in_card(
                    msa.pending,
                    msa.error.clone(),
                    move |_| show_offline.set(true),
                    {
                        let msa = msa.clone();
                        move |_| msa.start()
                    },
                )
                .into_element(),
            })
            .into_element();

        let page = onboarding_page(
            onboarding_illustration(IconType::OnboardingAccount),
            content,
            onboarding_nav(
                Some(Route::OnboardingLanguage {}),
                Route::OnboardingBundles {},
                has_account,
            ),
        );

        rect()
            .width(Size::fill())
            .height(Size::fill())
            .child(page)
            .maybe_child(show_offline.read().then(|| {
                offline_dialog(username, offline_uuid, offline_error, on_confirm_offline, show_offline)
            }))
            .maybe_child(msa.popup())
    }
}

fn account_preview(account: &MinecraftAccount) -> impl IntoElement {
    rect()
        .horizontal()
        .width(Size::fill())
        .spacing(24.)
        .child(
            rect()
                .horizontal()
                .spacing(12.)
                .cross_align(Alignment::Center)
                .child(
                    Avatar::new(account.id.to_string())
                        .width(Size::px(48.))
                        .height(Size::px(48.)),
                )
                .child(
                    rect()
                        .vertical()
                        .spacing(4.)
                        .child(
                            label()
                                .text(account.username.clone())
                                .font_size(text_size(16.))
                                .font_weight(FontWeight::SEMI_BOLD)
                                .color(colors::fg_primary()),
                        )
                        .child(
                            label()
                                .text(account.id.to_string())
                                .font_size(text_size(12.))
                                .color(colors::fg_secondary()),
                        ),
                ),
        )
        .into_element()
}

fn sign_in_card(
    pending: bool,
    error: Option<String>,
    on_open_offline: impl FnMut(Event<PressEventData>) + 'static,
    on_add: impl FnMut(Event<PressEventData>) + 'static,
) -> impl IntoElement {
    rect()
        .vertical()
        .spacing(12.)
        .cross_align(Alignment::Start)
        .child(
            rect()
                .horizontal()
                .spacing(8.)
                .child(
                    Button::new()
                        .primary()
                        .large()
                        .enabled(!pending)
                        .on_press(on_add)
                        .child(Icon::new(IconType::Globe01).size(16.))
                        .text(if pending {
                            t("oneclient.onboarding.account.signing_in")
                        } else {
                            t("oneclient.onboarding.account.add")
                        }),
                )
                .child(
                    Button::new()
                        .secondary()
                        .large()
                        .on_press(on_open_offline)
                        .child(Icon::new(IconType::Plus).size(16.))
                        .text(t("oneclient.onboarding.account.add_offline")),
                ),
        )
        .maybe_child(error.map(|message| {
            rect()
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(6.)
                .child(
                    Icon::new(IconType::AlertTriangle)
                        .size(13.)
                        .color(colors::danger()),
                )
                .child(
                    label()
                        .text(message)
                        .font_size(text_size(12.))
                        .color(colors::danger()),
                )
                .into_element()
        }))
        .into_element()
}

fn offline_dialog(
    username: State<String>,
    uuid_preview: Option<String>,
    error: Option<String>,
    on_confirm: impl FnMut(Event<PressEventData>) + 'static,
    mut show_offline: State<bool>,
) -> impl IntoElement {
    OverlayPopup::new()
        .on_close(move |()| show_offline.set(false))
        .child(
            rect()
                .width(Size::window_percent(100.))
                .height(Size::window_percent(100.))
                .center()
                .child(
                    rect()
                        .vertical()
                        .width(Size::px(380.))
                        .max_width(Size::window_percent(90.))
                        .spacing(16.)
                        .padding(Gaps::new_all(20.))
                        .corner_radius(rounded(16.))
                        .background(colors::page_elevated())
                        .border(border_all_color(1., colors::component_border()))
                        .child(
                            label()
                                .text(t("oneclient.settings.accounts.offline.title"))
                                .font_size(text_size(18.))
                                .font_weight(FontWeight::SEMI_BOLD)
                                .color(colors::fg_primary()),
                        )
                        .child(
                            rect()
                                .vertical()
                                .width(Size::fill())
                                .spacing(6.)
                                .child(field_label(t(
                                    "oneclient.settings.accounts.offline.username",
                                )))
                                .child(TextInput::new(username).placeholder(t(
                                    "oneclient.settings.accounts.offline.username_placeholder",
                                ))),
                        )
                        .child(
                            rect()
                                .vertical()
                                .width(Size::fill())
                                .spacing(6.)
                                .child(field_label("UUID"))
                                .child(
                                    label()
                                        .text(uuid_preview.unwrap_or_else(|| "-".to_string()))
                                        .font_size(text_size(12.))
                                        .color(colors::fg_secondary()),
                                ),
                        )
                        .map(error, |el, msg| {
                            el.child(
                                rect()
                                    .horizontal()
                                    .cross_align(Alignment::Center)
                                    .spacing(6.)
                                    .child(
                                        Icon::new(IconType::AlertTriangle)
                                            .size(13.)
                                            .color(colors::danger()),
                                    )
                                    .child(
                                        label()
                                            .text(msg)
                                            .font_size(text_size(12.))
                                            .color(colors::danger()),
                                    ),
                            )
                        })
                        .child(
                            rect()
                                .horizontal()
                                .width(Size::fill())
                                .main_align(Alignment::End)
                                .spacing(8.)
                                .child(
                                    Button::new()
                                        .ghost()
                                        .on_press(move |_| show_offline.set(false))
                                        .text(t("oneclient.common.cancel")),
                                )
                                .child(
                                    Button::new()
                                        .primary()
                                        .on_press(on_confirm)
                                        .child(Icon::new(IconType::Plus).size(16.))
                                        .text(t("oneclient.settings.accounts.offline.confirm")),
                                ),
                        ),
                ),
        )
        .into_element()
}

fn field_label(text: &str) -> impl IntoElement {
    label()
        .text(text.to_string())
        .font_size(text_size(11.))
        .font_weight(FontWeight::MEDIUM)
        .color(colors::fg_secondary())
        .into_element()
}

fn mutation_err_text<M>(mutation: &UseMutation<M>) -> Option<String>
where
    M: MutationCapability,
    M::Err: std::fmt::Display,
{
    match &*mutation.read().state() {
        MutationStateData::Settled { res: Err(err), .. } => Some(err.to_string()),
        MutationStateData::Loading {
            res: Some(Err(err)),
        } => Some(err.to_string()),
        _ => None,
    }
}
