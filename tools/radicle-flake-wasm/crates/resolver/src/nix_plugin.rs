use crate::{
    git_transport_url, resolve_with_rev, LockedFetchMetadata, ResolveError, ResolveRequest,
};
use nix_wasm_rust::{panic as wasm_panic, Value};

#[no_mangle]
pub extern "C" fn resolve(args: Value) -> Value {
    match resolve_value(args) {
        Ok(value) => value,
        Err(err) => wasm_panic(&err.to_string()),
    }
}

fn resolve_value(args: Value) -> Result<Value, ResolveError> {
    let request = ResolveRequest {
        rid: required_string_attr(&args, "rid")?,
        seed: required_string_attr(&args, "seed")?,
        branch: required_string_attr(&args, "branch")?,
    };
    let url = git_transport_url(&request)?;
    let branch = request.branch.clone();
    let rev = resolve_rev(&args, &url, &branch)?;
    let metadata = resolve_with_rev(&request, rev)?;

    Ok(metadata_to_value(&metadata))
}

fn required_string_attr(args: &Value, field: &'static str) -> Result<String, ResolveError> {
    let value = args
        .get_attr(field)
        .ok_or(ResolveError::MissingField(field))?;
    Ok(value.get_string())
}

fn resolve_rev(args: &Value, url: &str, branch: &str) -> Result<String, ResolveError> {
    if let Some(rev) = args.get_attr("rev") {
        return Ok(rev.get_string());
    }

    let resolve_rev = args
        .get_attr("resolveRev")
        .ok_or(ResolveError::MissingField("resolveRev"))?;
    let request = Value::make_attrset(&[
        ("url", Value::make_string(url)),
        ("ref", Value::make_string(branch)),
    ]);

    Ok(resolve_rev.call(&[request]).get_string())
}

fn metadata_to_value(metadata: &LockedFetchMetadata) -> Value {
    match metadata {
        LockedFetchMetadata::Git { url, git_ref, rev } => Value::make_attrset(&[
            ("kind", Value::make_string("git")),
            ("url", Value::make_string(url)),
            ("ref", Value::make_string(git_ref)),
            ("rev", Value::make_string(rev)),
        ]),
    }
}
