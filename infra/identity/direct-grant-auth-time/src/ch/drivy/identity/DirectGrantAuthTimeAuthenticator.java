package ch.drivy.identity;

import java.util.List;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.authenticators.directgrant.AbstractDirectGrantAuthenticator;
import org.keycloak.common.util.Time;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.services.managers.AuthenticationManager;

/** Records a credential check, never a token issuance or refresh time. */
public final class DirectGrantAuthTimeAuthenticator extends AbstractDirectGrantAuthenticator {
    public static final String ID = "drivy-direct-grant-auth-time";

    @Override
    public void authenticate(AuthenticationFlowContext context) {
        // Fail closed if the flow was accidentally installed before password validation.
        if (context.getUser() == null || !"true".equals(context.getAuthenticationSession()
                .getAuthNote(AuthenticationManager.PASSWORD_VALIDATED))) {
            context.failure(AuthenticationFlowError.INVALID_CREDENTIALS,
                    errorResponse(401, "invalid_grant", "Invalid user credentials"));
            return;
        }
        // TokenManager transfers this note to the new user session after the entire flow succeeds.
        context.getAuthenticationSession().setUserSessionNote(
                AuthenticationManager.AUTH_TIME, Integer.toString(Time.currentTime()));
        context.success();
    }

    @Override public boolean requiresUser() { return true; }
    @Override public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) { return true; }
    @Override public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) { }
    @Override public boolean isUserSetupAllowed() { return false; }
    @Override public String getDisplayType() { return "Drivy · Direct grant authentication time"; }
    @Override public String getReferenceCategory() { return "auth-time"; }
    @Override public boolean isConfigurable() { return false; }
    @Override public AuthenticationExecutionModel.Requirement[] getRequirementChoices() {
        return new AuthenticationExecutionModel.Requirement[] { AuthenticationExecutionModel.Requirement.REQUIRED };
    }
    @Override public String getHelpText() { return "Record authentication time after the required password and OTP validators."; }
    @Override public List<ProviderConfigProperty> getConfigProperties() { return List.of(); }
    @Override public String getId() { return ID; }
}
