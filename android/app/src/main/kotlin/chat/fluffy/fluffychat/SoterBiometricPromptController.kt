package chat.fluffy.fluffychat

import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * 管理 Soter 指纹认证期间的原生底部弹窗，补齐类似 androidx.biometric 的视觉反馈。
 *
 * @param activity 当前承载 Flutter 的 Activity
 */
class SoterBiometricPromptController(
    private var activity: FlutterFragmentActivity,
) {
    private var dialog: Dialog? = null
    private var subtitleView: TextView? = null
    private var internalDismiss = false

    /**
     * 更新当前可用的 Activity。
     *
     * @param activity 新的前台 Activity
     * @return 无返回值
     */
    fun updateActivity(activity: FlutterFragmentActivity) {
        if (this.activity === activity) {
            return
        }
        hide()
        this.activity = activity
    }

    /**
     * 显示 Soter 指纹弹窗，并注册用户主动取消时的回调。
     *
     * @param promptText 弹窗标题、副标题和取消按钮文案
     * @param onCancelRequested 用户改为输入 PIN 或返回时触发的取消动作
     * @return 无返回值
     */
    fun show(promptText: SoterPromptText, onCancelRequested: () -> Unit) {
        activity.runOnUiThread {
            if (activity.isFinishing || activity.isDestroyed) {
                return@runOnUiThread
            }

            val currentDialog = dialog ?: buildDialog(promptText, onCancelRequested)
            bindPromptText(currentDialog, promptText)
            if (!currentDialog.isShowing) {
                currentDialog.show()
            }
        }
    }

    /**
     * 用认证帮助文案刷新弹窗副标题。
     *
     * @param message Soter 回调返回的提示信息
     * @param isError 是否按错误态着色
     * @return 无返回值
     */
    fun updateMessage(message: CharSequence?, isError: Boolean = false) {
        val safeMessage = message?.toString()?.trim().orEmpty()
        if (safeMessage.isEmpty()) {
            return
        }
        activity.runOnUiThread {
            subtitleView?.text = safeMessage
            subtitleView?.setTextColor(
                if (isError) {
                    activity.getColor(R.color.soter_prompt_error_text)
                } else {
                    activity.getColor(R.color.soter_prompt_secondary_text)
                },
            )
        }
    }

    /**
     * 关闭当前 Soter 指纹弹窗，不触发用户取消逻辑。
     *
     * @return 无返回值
     */
    fun hide() {
        activity.runOnUiThread {
            val currentDialog = dialog ?: return@runOnUiThread
            internalDismiss = true
            currentDialog.dismiss()
            internalDismiss = false
            dialog = null
            subtitleView = null
        }
    }

    /**
     * 构建底部弹窗实例，并配置窗口属性和取消监听。
     *
     * @param promptText 弹窗初始文案
     * @param onCancelRequested 用户主动取消时的回调
     * @return 创建好的 Dialog
     */
    private fun buildDialog(
        promptText: SoterPromptText,
        onCancelRequested: () -> Unit,
    ): Dialog {
        val contentView =
            LayoutInflater.from(activity).inflate(R.layout.dialog_soter_biometric_prompt, null)
        val createdDialog = Dialog(activity)
        createdDialog.setContentView(contentView)
        createdDialog.setCancelable(true)
        createdDialog.setCanceledOnTouchOutside(false)
        createdDialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setDimAmount(0.45f)
            setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            setGravity(Gravity.BOTTOM)
            attributes =
                attributes?.apply {
                    width = WindowManager.LayoutParams.MATCH_PARENT
                }
        }
        createdDialog.setOnCancelListener {
            if (!internalDismiss) {
                onCancelRequested()
            }
        }
        contentView.findViewById<View>(R.id.soterPromptNegativeButton).setOnClickListener {
            onCancelRequested()
        }
        contentView.findViewById<ImageButton>(R.id.soterPromptCloseButton).setOnClickListener {
            onCancelRequested()
        }
        dialog = createdDialog
        subtitleView = contentView.findViewById(R.id.soterPromptSubtitle)
        bindPromptText(createdDialog, promptText)
        return createdDialog
    }

    /**
     * 将业务侧传入的文案绑定到弹窗视图。
     *
     * @param dialog 当前展示中的 Dialog
     * @param promptText 弹窗标题、副标题和取消按钮文案
     * @return 无返回值
     */
    private fun bindPromptText(dialog: Dialog, promptText: SoterPromptText) {
        dialog.findViewById<TextView>(R.id.soterPromptAppName)?.text = appLabel()
        dialog.findViewById<TextView>(R.id.soterPromptTitle)?.text = promptText.title
        dialog.findViewById<TextView>(R.id.soterPromptSubtitle)?.apply {
            text = promptText.subtitle
            setTextColor(activity.getColor(R.color.soter_prompt_secondary_text))
        }
        dialog.findViewById<TextView>(R.id.soterPromptNegativeButton)?.text = promptText.negativeButton
        dialog.findViewById<ImageView>(R.id.soterPromptAppIcon)?.setImageResource(R.mipmap.ic_launcher)
    }

    /**
     * 读取应用显示名称，用于弹窗头部展示。
     *
     * @return 当前应用名
     */
    private fun appLabel(): String {
        return activity.applicationInfo.loadLabel(activity.packageManager).toString()
    }
}

/**
 * 承载 Soter 弹窗所需的展示文案。
 *
 * @param title 主标题
 * @param subtitle 副标题
 * @param negativeButton 底部取消按钮文案
 */
data class SoterPromptText(
    val title: String,
    val subtitle: String,
    val negativeButton: String,
)
