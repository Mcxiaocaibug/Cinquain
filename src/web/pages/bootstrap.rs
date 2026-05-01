use axum::{
	Router,
	extract::{State, rejection::FormRejection},
	http::StatusCode,
	response::{IntoResponse, Response},
	routing::get,
};
use validator::{Validate, ValidationError, ValidationErrors};

use crate::{
	WebError, form,
	pages::components::form::Form,
	template,
};

template! {
	struct Bootstrap<'a> use "bootstrap.html.j2" {
		server_name: &'a str,
		support_email: Option<String>,
		form: Option<Form<'static>>,
		message: Option<String>,
		message_tone: &'static str,
		success_user_id: Option<String>
	}
}

form! {
	struct BootstrapForm {
		#[validate(length(min = 1, message = "Bootstrap secret cannot be empty"))]
		bootstrap_secret: String where {
			input_type: "password",
			label: "Bootstrap secret",
			autocomplete: "current-password"
		},

		#[validate(length(min = 1, message = "Username cannot be empty"))]
		username: String where {
			input_type: "text",
			label: "Administrator username",
			autocomplete: "username"
		},

		#[validate(length(min = 12, message = "Password should be at least 12 characters"))]
		password: String where {
			input_type: "password",
			label: "Administrator password",
			autocomplete: "new-password"
		},

		#[validate(must_match(other = "password", message = "Passwords must match"))]
		confirm_password: String where {
			input_type: "password",
			label: "Confirm password",
			autocomplete: "new-password"
		}

		submit: "Create administrator"
	}
}

pub(crate) fn build() -> Router<crate::State> {
	Router::new()
		.route("/bootstrap", get(get_bootstrap).post(post_bootstrap))
		.route(
			"/_continuwuity/bootstrap",
			get(get_bootstrap).post(post_bootstrap),
		)
}

async fn get_bootstrap(State(services): State<crate::State>) -> Result<Response, WebError> {
	if let Some(message) = bootstrap_unavailable_message(&services) {
		return Ok(bootstrap_page(&services, None, Some(message), "info", None));
	}

	Ok(bootstrap_page(
		&services,
		Some(BootstrapForm::build(None)),
		None,
		"info",
		None,
	))
}

async fn post_bootstrap(
	State(services): State<crate::State>,
	form: Result<axum::Form<BootstrapForm>, FormRejection>,
) -> Result<Response, WebError> {
	let axum::Form(form) = form?;

	if let Some(message) = bootstrap_unavailable_message(&services) {
		return Ok((
			StatusCode::CONFLICT,
			bootstrap_page(&services, None, Some(message), "info", None),
		)
			.into_response());
	}

	let mut validation_errors = form.validate().err();

	if !services.firstrun.check_bootstrap_secret(&form.bootstrap_secret) {
		add_field_error(
			validation_errors.get_or_insert_with(ValidationErrors::new),
			"bootstrap_secret",
			"Bootstrap secret is incorrect",
		);
	}

	if form.username.trim().is_empty() {
		add_field_error(
			validation_errors.get_or_insert_with(ValidationErrors::new),
			"username",
			"Username cannot be empty",
		);
	}

	if let Some(errors) = validation_errors {
		return Ok((
			StatusCode::BAD_REQUEST,
			bootstrap_page(
				&services,
				Some(BootstrapForm::build(Some(errors))),
				Some(
					"Fix the highlighted fields, then submit the bootstrap form again."
						.to_owned(),
				),
				"error",
				None,
			),
		)
			.into_response());
	}

	match services
		.firstrun
		.bootstrap_first_admin(&form.username, &form.password)
		.await
	{
		| Ok(user_id) => Ok(bootstrap_page(
			&services,
			None,
			Some("Initial administrator created successfully.".to_owned()),
			"success",
			Some(user_id.to_string()),
		)),
		| Err(error) => Ok((
			StatusCode::BAD_REQUEST,
			bootstrap_page(
				&services,
				Some(BootstrapForm::build(None)),
				Some(error.to_string()),
				"error",
				None,
			),
		)
			.into_response()),
	}
}

fn bootstrap_page(
	services: &crate::State,
	form: Option<Form<'static>>,
	message: Option<String>,
	message_tone: &'static str,
	success_user_id: Option<String>,
) -> Response {
	Bootstrap::new(
		services,
		services.globals.server_name().as_str(),
		services.config.well_known.support_email.clone(),
		form,
		message,
		message_tone,
		success_user_id,
	)
	.into_response()
}

fn bootstrap_unavailable_message(services: &crate::State) -> Option<String> {
	if !services.firstrun.is_first_run() {
		Some(
			"Initial bootstrap is already complete. Sign in with your administrator account \
			 and continue from the support page."
				.to_owned(),
		)
	} else if !services.firstrun.bootstrap_required() {
		Some(
			"Guided bootstrap is not enabled on this server. Configure `bootstrap_secret` and \
			 restart if you want the built-in setup flow."
				.to_owned(),
		)
	} else {
		None
	}
}

fn add_field_error(errors: &mut ValidationErrors, field: &'static str, message: &'static str) {
	let mut error = ValidationError::new("invalid");
	error.message = Some(message.into());
	errors.add(field, error);
}
