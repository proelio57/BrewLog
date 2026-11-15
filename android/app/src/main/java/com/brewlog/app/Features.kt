package com.brewlog.app

/** Features that are built but switched off in the UI. */
object Features {
    /**
     * "Ask Claude" (bean advice): hidden for now while the AI connection is reworked (other providers, sign-in).
     * The code stays (`BeanAdvisor`, `AskClaudeScreens`, the `Routes.AI` and `beanAdvice` routes); set this to `true` to
     * show it again. Same switch on iOS: `Features.askAI`. (Not a `const`, so the compiler doesn't flag the hidden code.)
     */
    val askAi: Boolean = false
}
