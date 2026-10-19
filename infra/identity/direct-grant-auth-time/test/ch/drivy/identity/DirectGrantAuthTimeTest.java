package ch.drivy.identity;

import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.common.util.Time;
import org.keycloak.models.UserModel;
import org.keycloak.services.managers.AuthenticationManager;
import org.keycloak.sessions.AuthenticationSessionModel;

/** No external test dependency; no credential, account or token fixture. */
public final class DirectGrantAuthTimeTest {
    @SuppressWarnings("unchecked")
    private static <T> T proxy(Class<T> type, java.lang.reflect.InvocationHandler handler) {
        return (T) Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[] {type}, handler);
    }

    private static void check(boolean userPresent, String validated, boolean expectedSuccess) {
        Map<String,String> notes=new HashMap<>();boolean[] result={false,false};
        AuthenticationSessionModel session=proxy(AuthenticationSessionModel.class,(object,method,args)->switch(method.getName()) {
            case "getAuthNote" -> validated;
            case "setUserSessionNote" -> {notes.put((String)args[0],(String)args[1]);yield null;}
            default -> throw new AssertionError("Unexpected session operation");
        });
        UserModel user=userPresent?proxy(UserModel.class,(object,method,args)->null):null;
        AuthenticationFlowContext context=proxy(AuthenticationFlowContext.class,(object,method,args)->switch(method.getName()) {
            case "getUser" -> user;
            case "getAuthenticationSession" -> session;
            case "success" -> {result[0]=true;yield null;}
            case "failure" -> {result[1]=true;yield null;}
            default -> throw new AssertionError("Unexpected authentication operation");
        });
        int before=Time.currentTime();new DirectGrantAuthTimeAuthenticator().authenticate(context);int after=Time.currentTime();
        if(result[0]!=expectedSuccess||result[1]==expectedSuccess)throw new AssertionError("Credential guard failed");
        if(expectedSuccess) {
            int time=Integer.parseInt(notes.get(AuthenticationManager.AUTH_TIME));
            if(notes.size()!=1||time<before||time>after)throw new AssertionError("Authentication time invalid");
        } else if(!notes.isEmpty())throw new AssertionError("Refused authentication wrote a session note");
    }

    public static void main(String[] args) {
        check(true,"true",true);check(true,null,false);check(true,"false",false);check(false,"true",false);
        System.out.println("Identity provider: 4 credential guard checks passed.");
    }
}
