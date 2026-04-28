/*
Pool Management — 注册剧本（Recipes）+ 执行任务（Jobs）

设计：
 - 大部分商用 AI 服务无法无人值守注册（CAPTCHA / 实名 / 信用卡 / 设备指纹），
   所以默认走「半自动」(ManualMode = true)：
     用户点「入队」→ 系统给出操作步骤、所需材料、文档链接
     用户线下注册成功 → 点「录入结果」回填 Key → 系统自动入号池 + 可选建渠道
 - 少量站点可全自动：把 ManualMode 关掉、配 WebhookURL，由独立外部 worker 完成
*/

import React, { useEffect, useState, useMemo } from 'react';
import {
  Card,
  Table,
  Button,
  Space,
  Tag,
  Modal,
  Form,
  Switch,
  Banner,
  Typography,
  Empty,
  Descriptions,
  Popconfirm,
  Toast,
} from '@douyinfe/semi-ui';
import {
  IconRefresh,
  IconPlay,
  IconEdit,
  IconExternalOpen,
  IconTickCircle,
  IconClose,
  IconSetting,
} from '@douyinfe/semi-icons';
import { useTranslation } from 'react-i18next';
import { API } from '../../helpers/api';
import { showError, showSuccess } from '../../helpers';
import PoolPageLayout from './Layout';

const { Text, Title, Paragraph } = Typography;

const STATUS_TAG = {
  pending: { color: 'grey', text: '排队中' },
  manual_pending: { color: 'orange', text: '待录入结果' },
  running: { color: 'blue', text: '执行中' },
  success: { color: 'green', text: '成功' },
  failed: { color: 'red', text: '失败' },
  cancelled: { color: 'grey', text: '已取消' },
};

const DIFFICULTY_TAG = {
  easy: { color: 'green', text: '简单' },
  medium: { color: 'orange', text: '中等' },
  hard: { color: 'red', text: '困难' },
};

const IP_TAG = {
  any: { color: 'green', text: '任意 IP' },
  residential: { color: 'orange', text: '需住宅 IP' },
  specific_country: { color: 'red', text: '需指定国家 IP' },
};

const AUTOMATION_TAG = {
  full: { color: 'green', text: '可全自动', tip: '已实现自动 Runner，仅需邮箱即可注册' },
  sms_paid: {
    color: 'orange',
    text: '需付费接码',
    tip: '需要海外手机号 OTP，建议配置 sms-activate / 5sim 付费 API Key',
  },
  oauth_only: {
    color: 'violet',
    text: '仅 OAuth',
    tip: '必须 Google / GitHub OAuth 登录，无法全自动',
  },
  realname_only: {
    color: 'red',
    text: '需实名',
    tip: '国内服务必须手机号实名 + 风控严格，建议手动注册',
  },
  manual: { color: 'grey', text: '手动', tip: '复杂流程，建议手动完成' },
};

const safeParseList = (s) => {
  if (!s) return [];
  try {
    const r = JSON.parse(s);
    return Array.isArray(r) ? r : [];
  } catch (e) {
    return [];
  }
};

const Recipes = () => {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(false);
  const [recipes, setRecipes] = useState([]);
  const [jobs, setJobs] = useState([]);
  const [workerStatus, setWorkerStatus] = useState(null);

  const [editVisible, setEditVisible] = useState(false);
  const [editing, setEditing] = useState(null);
  const [editFormApi, setEditFormApi] = useState(null);

  const [stepsVisible, setStepsVisible] = useState(false);
  const [stepsRecipe, setStepsRecipe] = useState(null);

  const [enqueuedVisible, setEnqueuedVisible] = useState(false);
  const [enqueuedInfo, setEnqueuedInfo] = useState(null);

  const [submitVisible, setSubmitVisible] = useState(false);
  const [submitJob, setSubmitJob] = useState(null);
  const [submitRecipe, setSubmitRecipe] = useState(null);
  const [submitFormApi, setSubmitFormApi] = useState(null);

  const [autoCfgVisible, setAutoCfgVisible] = useState(false);
  const [autoCfg, setAutoCfg] = useState(null);
  const [autoCfgFormApi, setAutoCfgFormApi] = useState(null);

  const fetchData = async () => {
    setLoading(true);
    try {
      const [recRes, wsRes] = await Promise.all([
        API.get('/api/pool/recipes'),
        API.get('/api/pool/worker/status').catch(() => ({})),
      ]);
      if (recRes?.data?.success) {
        setRecipes(recRes.data.data.recipes || []);
        setJobs(recRes.data.data.jobs || []);
      } else {
        showError(recRes?.data?.message || t('加载失败'));
      }
      if (wsRes?.data?.success) {
        setWorkerStatus(wsRes.data.data);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    } finally {
      setLoading(false);
    }
  };

  const openAutoCfg = async () => {
    try {
      const res = await API.get('/api/pool/automation/config');
      if (res?.data?.success) {
        setAutoCfg(res.data.data);
        setAutoCfgVisible(true);
        setTimeout(() => {
          autoCfgFormApi?.setValues({
            PoolEmailProvider:
              res.data.data.current?.PoolEmailProvider || 'mailtm',
            PoolSmsProvider: res.data.data.current?.PoolSmsProvider || '',
            PoolSmsActivateApiKey:
              res.data.data.current?.PoolSmsActivateApiKey || '',
            PoolFivesimApiKey: res.data.data.current?.PoolFivesimApiKey || '',
          });
        }, 0);
      } else {
        showError(res?.data?.message || t('加载失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const handleAutoCfgSubmit = async (values) => {
    try {
      const payload = { ...values };
      // 掩码值（"****1234" / 留空）不发送 → 后端不更新
      ['PoolSmsActivateApiKey', 'PoolFivesimApiKey'].forEach((k) => {
        if (
          payload[k] &&
          payload[k].startsWith('****') &&
          payload[k].length <= 12
        ) {
          payload[k] = '[unchanged]';
        }
      });
      const res = await API.put('/api/pool/automation/config', payload);
      if (res?.data?.success) {
        showSuccess(t('已保存'));
        setAutoCfgVisible(false);
      } else {
        showError(res?.data?.message);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  useEffect(() => {
    fetchData();
    const it = setInterval(fetchData, 8000);
    return () => clearInterval(it);
  }, []);

  const recipeMap = useMemo(() => {
    const m = {};
    for (const r of recipes) m[r.key] = r;
    return m;
  }, [recipes]);

  const openEdit = (record) => {
    setEditing({ ...record });
    setEditVisible(true);
  };

  const handleEditSubmit = async (values) => {
    try {
      const payload = {
        ...values,
        manual_mode:
          typeof values.manual_mode === 'boolean' ? values.manual_mode : null,
      };
      const res = await API.put(`/api/pool/recipes/${editing.id}`, payload);
      if (res?.data?.success) {
        showSuccess(t('已保存'));
        setEditVisible(false);
        fetchData();
      } else {
        showError(res?.data?.message || t('保存失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const openSteps = (record) => {
    setStepsRecipe(record);
    setStepsVisible(true);
  };

  const handleEnqueue = async (record) => {
    if (!record.enabled) {
      showError(t('请先在「编辑」中启用此 Recipe'));
      return;
    }
    try {
      const res = await API.post(`/api/pool/recipes/${record.key}/enqueue`, {});
      if (res?.data?.success) {
        const d = res.data.data;
        showSuccess(`${t('已创建任务')} job_id=${d.job_id}`);
        if (d.mode === 'manual') {
          setEnqueuedInfo({ ...d, recipe: record });
          setEnqueuedVisible(true);
        }
        fetchData();
      } else {
        showError(res?.data?.message || t('入队失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const openSubmit = (job) => {
    const recipe = recipeMap[job.recipe_key];
    setSubmitJob(job);
    setSubmitRecipe(recipe);
    setSubmitVisible(true);
    setTimeout(() => {
      submitFormApi?.reset();
      submitFormApi?.setValues({
        account_name: `${recipe?.provider || job.recipe_key}-${Date.now() % 10000}`,
        balance_usd: 0,
        group_name: 'default',
        create_channel: !!recipe?.channel_type,
      });
    }, 0);
  };

  const handleSubmitResult = async (values) => {
    if (!submitJob) return;
    try {
      const res = await API.post(
        `/api/pool/jobs/${submitJob.id}/manual-result`,
        {
          ...values,
          balance_usd: Number(values.balance_usd) || 0,
        },
      );
      if (res?.data?.success) {
        const d = res.data.data;
        showSuccess(
          `${t('已入号池')}：account_id=${d.pool_account_id}` +
            (d.channel_id ? `，channel_id=${d.channel_id}` : ''),
        );
        setSubmitVisible(false);
        fetchData();
      } else {
        showError(res?.data?.message || t('回填失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const handleCancelJob = async (id) => {
    try {
      const res = await API.post(`/api/pool/jobs/${id}/cancel`, {});
      if (res?.data?.success) {
        showSuccess(t('已取消'));
        fetchData();
      } else {
        showError(res?.data?.message);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const handleRetryJob = async (id) => {
    try {
      const res = await API.post(`/api/pool/jobs/${id}/retry`, {});
      if (res?.data?.success) {
        showSuccess(`${t('已创建重试任务')} job_id=${res.data.data.job_id}`);
        fetchData();
      } else {
        showError(res?.data?.message);
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const recipeColumns = [
    {
      title: t('名称'),
      dataIndex: 'name',
      width: 220,
      render: (v, r) => (
        <div>
          <div className='font-medium'>{v}</div>
          <div className='text-xs text-gray-500 font-mono'>{r.key}</div>
        </div>
      ),
    },
    {
      title: t('Provider'),
      dataIndex: 'provider',
      width: 110,
      render: (v) => <Tag>{v}</Tag>,
    },
    {
      title: t('模式'),
      dataIndex: 'manual_mode',
      width: 90,
      render: (v) =>
        v ? (
          <Tag color='violet' size='small'>
            {t('半自动')}
          </Tag>
        ) : (
          <Tag color='blue' size='small'>
            {t('全自动')}
          </Tag>
        ),
    },
    {
      title: t('自动化能力'),
      dataIndex: 'automation_capability',
      width: 110,
      render: (v) => {
        const a = AUTOMATION_TAG[v] || AUTOMATION_TAG.manual;
        return (
          <Tag color={a.color} size='small' title={a.tip}>
            {a.text}
          </Tag>
        );
      },
    },
    {
      title: t('难度'),
      dataIndex: 'difficulty',
      width: 80,
      render: (v) => {
        const d = DIFFICULTY_TAG[v] || { color: 'grey', text: v };
        return <Tag color={d.color}>{d.text}</Tag>;
      },
    },
    {
      title: t('IP 要求'),
      dataIndex: 'ip_requirement',
      width: 110,
      render: (v) => {
        const i = IP_TAG[v] || { color: 'grey', text: v };
        return (
          <Tag color={i.color} size='small'>
            {i.text}
          </Tag>
        );
      },
    },
    {
      title: t('启用'),
      dataIndex: 'enabled',
      width: 70,
      render: (v) =>
        v ? <Tag color='green'>ON</Tag> : <Tag color='grey'>OFF</Tag>,
    },
    {
      title: t('成功 / 失败'),
      width: 90,
      render: (_, r) => (
        <span>
          <span className='text-green-600'>{r.success_count}</span>
          {' / '}
          <span className='text-red-500'>{r.failure_count}</span>
        </span>
      ),
    },
    {
      title: t('操作'),
      width: 280,
      render: (_, r) => (
        <Space>
          <Button size='small' onClick={() => openSteps(r)}>
            {t('查看步骤')}
          </Button>
          <Button size='small' icon={<IconEdit />} onClick={() => openEdit(r)}>
            {t('编辑')}
          </Button>
          <Button
            size='small'
            type='primary'
            theme='solid'
            icon={<IconPlay />}
            disabled={!r.enabled}
            onClick={() => handleEnqueue(r)}
          >
            {t('入队')}
          </Button>
        </Space>
      ),
    },
  ];

  const jobColumns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    {
      title: t('Recipe'),
      dataIndex: 'recipe_key',
      render: (v) => <span className='font-mono text-xs'>{v}</span>,
    },
    {
      title: t('状态'),
      dataIndex: 'status',
      render: (v) => {
        const s = STATUS_TAG[v] || { color: 'grey', text: v };
        return <Tag color={s.color}>{s.text}</Tag>;
      },
    },
    {
      title: t('开始'),
      dataIndex: 'started_at',
      render: (v) => (v ? new Date(v * 1000).toLocaleString() : '-'),
    },
    {
      title: t('完成'),
      dataIndex: 'finished_at',
      render: (v) => (v ? new Date(v * 1000).toLocaleString() : '-'),
    },
    {
      title: t('错误'),
      dataIndex: 'error_msg',
      width: 200,
      render: (v) =>
        v ? (
          <Button
            theme='borderless'
            type='danger'
            size='small'
            onClick={() => {
              Modal.error({
                title: t('错误详情'),
                width: 640,
                content: (
                  <pre
                    style={{ whiteSpace: 'pre-wrap', margin: 0, fontSize: 12 }}
                  >
                    {v}
                  </pre>
                ),
              });
            }}
          >
            {v.length > 30 ? v.slice(0, 30) + '…' : v}
          </Button>
        ) : (
          '-'
        ),
    },
    {
      title: t('创建'),
      dataIndex: 'created_time',
      render: (v) => (v ? new Date(v * 1000).toLocaleString() : '-'),
    },
    {
      title: t('操作'),
      width: 220,
      render: (_, r) => (
        <Space>
          {r.status === 'manual_pending' && (
            <>
              <Button
                size='small'
                type='primary'
                theme='solid'
                icon={<IconTickCircle />}
                onClick={() => openSubmit(r)}
              >
                {t('录入结果')}
              </Button>
              <Popconfirm
                title={t('确认取消？')}
                onConfirm={() => handleCancelJob(r.id)}
              >
                <Button size='small' icon={<IconClose />}>
                  {t('取消')}
                </Button>
              </Popconfirm>
            </>
          )}
          {(r.status === 'pending' || r.status === 'running') && (
            <Popconfirm
              title={t('确认取消？')}
              onConfirm={() => handleCancelJob(r.id)}
            >
              <Button size='small' icon={<IconClose />}>
                {t('取消')}
              </Button>
            </Popconfirm>
          )}
          {(r.status === 'failed' || r.status === 'cancelled') && (
            <Button size='small' onClick={() => handleRetryJob(r.id)}>
              {t('重试')}
            </Button>
          )}
        </Space>
      ),
    },
  ];

  return (
    <PoolPageLayout
      title={t('注册剧本')}
      subtitle={t(
        '内置主流 AI 服务的注册流程：操作步骤 + 所需材料 + 自动入号池',
      )}
      badge='Recipes'
      extra={
        <Space>
          <Button
            icon={<IconSetting />}
            size='small'
            onClick={openAutoCfg}
          >
            {t('自动化设置')}
          </Button>
          <Button
            icon={<IconRefresh />}
            size='small'
            onClick={fetchData}
            loading={loading}
          >
            {t('刷新')}
          </Button>
        </Space>
      }
    >
      <Banner
        type='info'
        description={
          <span>
            {t(
              '默认「半自动」：系统给出操作清单+所需材料，你线下完成后点「录入结果」自动入号池。',
            )}
            {' '}
            {t(
              '也可在「编辑」中关闭「半自动」改成「全自动」（chromedp + mail.tm），但会受目标站点风控/Cloudflare 影响。',
            )}
          </span>
        }
        closeIcon={null}
        className='mb-3'
      />

      {workerStatus && (
        <Card className='mb-3'>
          <Space spacing={20}>
            <Space>
              <Text strong>{t('Worker 状态')}:</Text>
              {workerStatus.running ? (
                <Tag color='green'>{t('运行中')}</Tag>
              ) : (
                <Tag color='grey'>{t('未启动')}</Tag>
              )}
            </Space>
            <Text type='tertiary'>
              {t('并发')} {workerStatus.inflight}/{workerStatus.max_concurrent}
            </Text>
            <Text type='tertiary'>
              {t('已注册全自动 Runner')}:{' '}
              {(workerStatus.runner_keys || []).length === 0 ? (
                <span>{t('无')}</span>
              ) : (
                (workerStatus.runner_keys || []).map((k) => (
                  <Tag key={k} size='small' color='blue' style={{ marginRight: 4 }}>
                    {k}
                  </Tag>
                ))
              )}
            </Text>
          </Space>
        </Card>
      )}

      <Card title={`${t('剧本清单')} (${recipes.length})`} className='mb-4'>
        <Table
          loading={loading}
          dataSource={recipes}
          columns={recipeColumns}
          rowKey='id'
          pagination={false}
          size='small'
        />
      </Card>

      <Card title={t('任务历史（最近 50 条）')}>
        {jobs.length === 0 ? (
          <Empty description={t('暂无执行任务')} />
        ) : (
          <Table
            dataSource={jobs}
            columns={jobColumns}
            rowKey='id'
            pagination={{ pageSize: 10 }}
            size='small'
          />
        )}
      </Card>

      {/* —— 操作步骤 Drawer / Modal —— */}
      <Modal
        title={`${stepsRecipe?.name || ''} — ${t('操作指南')}`}
        visible={stepsVisible}
        onCancel={() => setStepsVisible(false)}
        footer={
          <Space>
            <Button onClick={() => setStepsVisible(false)}>{t('关闭')}</Button>
            {stepsRecipe?.enabled && (
              <Button
                type='primary'
                theme='solid'
                icon={<IconPlay />}
                onClick={() => {
                  setStepsVisible(false);
                  handleEnqueue(stepsRecipe);
                }}
              >
                {t('入队此剧本')}
              </Button>
            )}
          </Space>
        }
        width={680}
      >
        {stepsRecipe && (
          <div>
            <Descriptions
              data={[
                { key: 'Provider', value: <Tag>{stepsRecipe.provider}</Tag> },
                {
                  key: t('难度'),
                  value: (
                    <Tag color={DIFFICULTY_TAG[stepsRecipe.difficulty]?.color}>
                      {DIFFICULTY_TAG[stepsRecipe.difficulty]?.text}
                    </Tag>
                  ),
                },
                {
                  key: 'IP',
                  value: (
                    <Tag color={IP_TAG[stepsRecipe.ip_requirement]?.color}>
                      {IP_TAG[stepsRecipe.ip_requirement]?.text}
                    </Tag>
                  ),
                },
                {
                  key: t('Key 形态'),
                  value: (
                    <span className='font-mono text-xs'>
                      {stepsRecipe.output_format || '-'}
                    </span>
                  ),
                },
                {
                  key: t('文档'),
                  value: stepsRecipe.doc_url ? (
                    <a
                      href={stepsRecipe.doc_url}
                      target='_blank'
                      rel='noreferrer'
                    >
                      <IconExternalOpen /> {stepsRecipe.doc_url}
                    </a>
                  ) : (
                    '-'
                  ),
                },
              ]}
              row
              size='small'
            />

            <Title heading={6} className='!mt-4'>
              {t('说明')}
            </Title>
            <Paragraph>{stepsRecipe.description || '-'}</Paragraph>

            <Title heading={6} className='!mt-4'>
              {t('所需材料')}
            </Title>
            <Space wrap>
              {safeParseList(stepsRecipe.required_materials).length === 0 ? (
                <Text type='tertiary'>-</Text>
              ) : (
                safeParseList(stepsRecipe.required_materials).map((m, i) => (
                  <Tag color='blue' key={i}>
                    {m}
                  </Tag>
                ))
              )}
            </Space>

            <Title heading={6} className='!mt-4'>
              {t('操作步骤')}
            </Title>
            <pre
              className='whitespace-pre-wrap text-sm'
              style={{
                background: 'var(--semi-color-fill-0)',
                padding: 12,
                borderRadius: 8,
              }}
            >
              {stepsRecipe.manual_steps || '-'}
            </pre>
          </div>
        )}
      </Modal>

      {/* —— 入队后的操作引导 —— */}
      <Modal
        title={t('任务已创建')}
        visible={enqueuedVisible}
        onCancel={() => setEnqueuedVisible(false)}
        footer={
          <Button type='primary' theme='solid' onClick={() => setEnqueuedVisible(false)}>
            {t('我知道了')}
          </Button>
        }
        width={620}
      >
        {enqueuedInfo && (
          <div>
            <Banner
              fullMode={false}
              type='success'
              description={enqueuedInfo.hint}
              closeIcon={null}
              className='mb-3'
            />
            {enqueuedInfo.doc_url && (
              <div className='mb-2'>
                <a
                  href={enqueuedInfo.doc_url}
                  target='_blank'
                  rel='noreferrer'
                >
                  <IconExternalOpen /> {t('打开注册页')}：
                  {enqueuedInfo.doc_url}
                </a>
              </div>
            )}
            <Title heading={6}>{t('操作步骤')}</Title>
            <pre
              className='whitespace-pre-wrap text-sm'
              style={{
                background: 'var(--semi-color-fill-0)',
                padding: 12,
                borderRadius: 8,
              }}
            >
              {enqueuedInfo.manual_steps}
            </pre>
            <div className='mt-2 text-xs text-gray-500'>
              {t('完成后到下方「任务历史」点「录入结果」回填 Key')}
            </div>
          </div>
        )}
      </Modal>

      {/* —— 录入结果 Modal —— */}
      <Modal
        title={`${t('录入结果')} — ${submitRecipe?.name || ''}`}
        visible={submitVisible}
        onCancel={() => setSubmitVisible(false)}
        footer={null}
        width={620}
      >
        <Banner
          type='info'
          description={t(
            'Key/Token 完整值仅用于（可选）自动建渠道；号池表中只保留脱敏串。',
          )}
          closeIcon={null}
          className='mb-3'
        />
        <Form
          getFormApi={setSubmitFormApi}
          onSubmit={handleSubmitResult}
          labelPosition='left'
          labelWidth={120}
        >
          <Form.Input
            field='account_name'
            label={t('账号名称')}
            rules={[{ required: true, message: t('必填') }]}
          />
          <Form.TextArea
            field='key_raw'
            label={t('Key / Token')}
            rows={3}
            placeholder={
              submitRecipe?.output_format
                ? `${t('期望格式')}: ${submitRecipe.output_format}`
                : ''
            }
            rules={[{ required: true, message: t('必填') }]}
          />
          <Form.InputNumber field='balance_usd' label={t('余额 ($)')} min={0} />
          <Form.Input field='group_name' label={t('分组')} />
          <Form.TextArea field='notes' label={t('备注')} rows={2} />
          <Form.Switch
            field='create_channel'
            label={
              submitRecipe?.channel_type
                ? `${t('同时新建渠道')} (type=${submitRecipe.channel_type})`
                : t('该剧本未指定 channel_type，无法自动建渠道')
            }
            disabled={!submitRecipe?.channel_type}
          />
          <div className='mt-3 text-right'>
            <Space>
              <Button onClick={() => setSubmitVisible(false)}>
                {t('取消')}
              </Button>
              <Button type='primary' theme='solid' htmlType='submit'>
                {t('提交并入号池')}
              </Button>
            </Space>
          </div>
        </Form>
      </Modal>

      {/* —— 编辑 Modal —— */}
      <Modal
        title={t('编辑剧本')}
        visible={editVisible}
        onCancel={() => setEditVisible(false)}
        footer={null}
        width={720}
        destroyOnClose
      >
        <Form
          key={editing?.id || 'new'}
          getFormApi={setEditFormApi}
          onSubmit={handleEditSubmit}
          initValues={editing || {}}
          labelPosition='left'
          labelWidth={140}
        >
          <Form.Input field='name' label={t('名称')} />
          <Form.Input field='version' label={t('版本')} />
          <Form.Switch
            field='enabled'
            label={t('启用 (允许入队)')}
            extraText={t('启用后才能在剧本列表点「入队」')}
          />
          <Form.Switch
            field='manual_mode'
            label={t('半自动模式')}
            extraText={t(
              '开启 = 系统只跟踪流程，注册由人完成后回填 Key；关闭 = 走全自动（已注册内部 Runner 时由本机 Worker 直接跑，否则才回退到 Webhook 外部 Worker）',
            )}
          />
          <Form.Input
            field='doc_url'
            label={t('注册地址')}
            placeholder='https://platform.example.com/signup'
          />
          <Form.Input
            field='output_format'
            label={t('Key 形态')}
            extraText={t('成功后期望拿到的 Key 字符串形式，如 sk-... (51 字符)')}
          />
          <Form.Select
            field='difficulty'
            label={t('难度')}
            optionList={[
              { label: t('简单'), value: 'easy' },
              { label: t('中等'), value: 'medium' },
              { label: t('困难'), value: 'hard' },
            ]}
          />
          <Form.Select
            field='ip_requirement'
            label={t('IP 要求')}
            optionList={[
              { label: t('任意 IP'), value: 'any' },
              { label: t('住宅 IP'), value: 'residential' },
              { label: t('指定国家'), value: 'specific_country' },
            ]}
            extraText={t(
              'OpenAI / Anthropic 强烈建议「住宅 IP」，机房 IP 几乎必失败',
            )}
          />
          <Form.InputNumber
            field='channel_type'
            label={t('渠道类型 ID')}
            min={0}
            extraText={t(
              '注册成功后自动建对应类型的 new-api 渠道，与「渠道管理」打通；0 = 不建渠道。常见：1=OpenAI、14=Anthropic、20=OpenRouter、24=Gemini、25=Moonshot',
            )}
          />
          <Form.Input
            field='channel_base_url'
            label={t('渠道 BaseURL')}
            extraText={t('留空表示用 new-api 该 Channel Type 的默认地址')}
          />
          <Form.Input
            field='sms_country'
            label={t('SMS 国家码')}
            placeholder='usa / russia / england / any'
            extraText={t(
              '5sim country slug；常用：usa（美国）/ russia / england / india。空 = any',
            )}
          />
          <Form.Input
            field='sms_product'
            label={t('SMS 产品码')}
            placeholder='openai / claudeai / google / any'
            extraText={t(
              '5sim product slug；常用：openai、claudeai、google、microsoft、discord、telegram。空 = any',
            )}
          />
          <Form.Input
            field='sms_operator'
            label={t('SMS 运营商')}
            placeholder='any'
            extraText={t('5sim operator slug；通常填 any')}
          />
          <Form.TextArea
            field='required_materials'
            label={t('所需材料 (JSON 数组)')}
            rows={2}
            extraText={t('JSON 数组字符串，如：["邮箱","海外手机号"]')}
          />
          <Form.TextArea
            field='manual_steps'
            label={t('操作步骤')}
            rows={6}
            extraText={t('每行一步；半自动模式下会展示给用户')}
          />
          <Form.TextArea field='description' label={t('说明')} rows={2} />
          <Form.Input
            field='webhook_url'
            label={t('Webhook URL（可选）')}
            placeholder={t('仅当外部 worker 接管时填')}
            extraText={t(
              '已实现内部 Runner 的剧本无需填此项；填后系统会回退到外部 worker',
            )}
          />
          <Form.TextArea
            field='config_json'
            label={t('Config JSON（可选）')}
            rows={3}
            placeholder={t('外部 worker 默认参数；保留为空即可')}
          />
          <div className='mt-3 text-right'>
            <Space>
              <Button onClick={() => setEditVisible(false)}>
                {t('取消')}
              </Button>
              <Button type='primary' theme='solid' htmlType='submit'>
                {t('保存')}
              </Button>
            </Space>
          </div>
        </Form>
      </Modal>

      {/* —— 自动化设置 Modal —— */}
      <Modal
        title={t('自动化设置')}
        visible={autoCfgVisible}
        onCancel={() => setAutoCfgVisible(false)}
        footer={null}
        width={680}
      >
        <Banner
          type='warning'
          description={
            <div>
              <div>
                {t(
                  '现实约束：免费临时邮箱 + 无打码服务，只能跑通 OpenRouter / Together / Cohere 等中等门槛站点；',
                )}
              </div>
              <div>
                {t(
                  '所有需要海外手机号 OTP 的服务（OpenAI / Anthropic / Mistral / xAI 等）必须配置付费接码 API Key，否则只能手动注册；',
                )}
              </div>
              <div>
                {t(
                  '国内服务（DeepSeek / Kimi / 智谱 / SiliconFlow / DashScope / MiniMax）实名要求严格，无法全自动。',
                )}
              </div>
            </div>
          }
          closeIcon={null}
          className='mb-3'
        />
        <Form
          getFormApi={setAutoCfgFormApi}
          onSubmit={handleAutoCfgSubmit}
          labelPosition='left'
          labelWidth={170}
        >
          <Form.Select
            field='PoolEmailProvider'
            label={t('临时邮箱')}
            optionList={(autoCfg?.email_providers || []).map((p) => ({
              label: p,
              value: p,
            }))}
            placeholder={t('默认按 mailtm → guerrilla → 1secmail 顺序 fallback')}
            extraText={t(
              'mailtm 最稳定（独立 API + 邮箱长期保留），但部分大厂已识别其域名；guerrilla 备份，1secmail 偶尔不可用。建议默认空表示按上述顺序自动 fallback。',
            )}
          />
          <Form.Select
            field='PoolSmsProvider'
            label={t('SMS 接码 Provider')}
            optionList={[
              { label: t('（不使用接码）'), value: '' },
              ...(autoCfg?.sms_providers || []).map((p) => ({
                label: p,
                value: p,
              })),
            ]}
            extraText={t(
              '5sim：付费 RUB 计价，OpenAI/ClaudeAI 在 USA 池约 0.15-0.41 RUB/号；sms-activate：另一家付费 USD 计价；mock：本地测试，立即返回假号 +0000... + 验证码 123456；onlinesim：免费层基本不可用。',
            )}
          />
          <Form.Input
            field='PoolFivesimApiKey'
            label='5sim.net API Key'
            placeholder={t('在 5sim.net 设置页获取（Bearer JWT Token）')}
            extraText={t(
              '5sim 推荐用：登录 5sim.net → Profile → API → Generate Token；JWT 格式 eyJ... 开头。已默认配置一个共享测试 token，余额耗尽后请自行充值或更换。',
            )}
          />
          <Form.Input
            field='PoolSmsActivateApiKey'
            label='sms-activate API Key'
            placeholder={t('在 sms-activate.org 个人中心获取')}
            extraText={t(
              'sms-activate.org 注册 → 充值 → 个人中心 → API Keys 复制；服务码示例：op=OpenAI、go=Google、tg=Telegram；国家码：187=USA、16=UK、22=India。',
            )}
          />
          {autoCfg?.sms_balance_usd >= 0 && (
            <div className='mb-2 text-xs text-gray-500'>
              {t('当前接码账户余额')}: {autoCfg.sms_balance_usd}{' '}
              {autoCfg?.sms_balance_unit || 'USD'}
            </div>
          )}
          <Banner
            type='info'
            description={
              <div className='text-xs'>
                {t('已注册的全自动 Runner')}:{' '}
                {(autoCfg?.runner_keys || []).join(', ') || t('无')}
              </div>
            }
            closeIcon={null}
            className='mb-3'
          />
          <div className='mt-3 text-right'>
            <Space>
              <Button onClick={() => setAutoCfgVisible(false)}>
                {t('取消')}
              </Button>
              <Button type='primary' theme='solid' htmlType='submit'>
                {t('保存')}
              </Button>
            </Space>
          </div>
        </Form>
      </Modal>
    </PoolPageLayout>
  );
};

export default Recipes;
